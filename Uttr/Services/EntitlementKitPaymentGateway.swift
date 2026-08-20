import AppKit
import Combine
import EntitlementKitCore
import EntitlementKitRevenueCat
import Foundation
import OSLog
import RevenueCat

/// Bridges EntitlementKit's web-billing gateway to Uttr's `PaymentGateway`
/// protocol. Every other call site keeps using `SubscriptionStatus`.
///
/// Uttr ships as a Developer ID DMG, so StoreKit in-app purchase is not
/// available. Checkout happens in the browser and returns through a custom
/// URL scheme — see `handleCallbackURL(_:)`.
@MainActor @Observable
final class EntitlementKitPaymentGateway: PaymentGateway {
    private(set) var subscriptionStatus: SubscriptionStatus = .free

    private let config: PricingConfig
    private let mapper: SubscriptionStatusMapper
    private let billing: WebBillingConfiguration?
    private let gateway: RevenueCatEntitlementGateway
    private let logger = Logger(subsystem: "com.uttr.app", category: "payment")

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    private static let installationIDKey = "com.uttr.installationID"
    private static let cachedStatusKey = "com.uttr.cachedSubscriptionStatus"

    var subscriptionManagementURL: URL? {
        config.customerPortalURL
    }

    init(pricingConfig: PricingConfig) {
        self.config = pricingConfig
        self.mapper = SubscriptionStatusMapper(config: pricingConfig)
        self.billing = pricingConfig.webPurchaseURL.map { url in
            WebBillingConfiguration(
                purchaseLink: url,
                packageIDsByPlanID: pricingConfig.packageIDsByPlanID,
                callbackScheme: pricingConfig.callbackScheme
            )
        }
        self.gateway = RevenueCatEntitlementGateway(
            apiKey: pricingConfig.revenueCatAPIKey,
            entitlementID: pricingConfig.entitlementID,
            lifetimePlanIDs: [pricingConfig.lifetimeProductID],
            identity: UserDefaultsInstallationIdentity(key: Self.installationIDKey),
            statusStore: UserDefaultsEntitlementStatusStore(key: Self.cachedStatusKey)
        )

        // The gateway restores its cached status during init, so seed from it
        // to avoid a frame of `.free` on launch.
        subscriptionStatus = mapper.subscriptionStatus(from: gateway.status)
        observeGateway()
    }

    private func observeGateway() {
        gateway.$status
            .sink { [weak self] status in
                guard let self else { return }
                self.subscriptionStatus = self.mapper.subscriptionStatus(from: status)
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func configure() async {
        Purchases.logLevel = .warn

        if let billing {
            for issue in billing.validationIssues {
                logger.error("Web billing misconfigured: \(String(describing: issue), privacy: .public)")
            }
        } else {
            logger.warning("No web purchase link configured — checkout is unavailable")
        }

        await gateway.configure()
    }

    // MARK: - Checkout

    /// Opens the anonymous Web Purchase Link in the default browser. Opening
    /// checkout is not a purchase: the result is always `.pending` and access
    /// is granted only when redemption or `customerInfoStream` confirms it.
    func purchase(_ product: SubscriptionProduct) async throws -> PurchaseResult {
        guard let billing else {
            throw PaymentError.purchaseFailed("Checkout is not configured in this build.")
        }

        switch WebPurchaseLinkBuilder.buildURL(configuration: billing, planID: product.plan.rawValue) {
        case .success(let url):
            NSWorkspace.shared.open(url)
            return .pending
        case .failure(let error):
            logger.error("Could not build checkout link: \(String(describing: error), privacy: .public)")
            throw PaymentError.purchaseFailed("Could not open checkout. Please try again.")
        }
    }

    /// Web Billing has no StoreKit receipt to restore from. Recovery runs
    /// through the redemption link RevenueCat emails to the billing address,
    /// so this opens the customer portal rather than querying a receipt.
    func restorePurchases() async throws {
        guard let url = config.customerPortalURL else {
            throw PaymentError.purchaseFailed("The subscription portal is not configured in this build.")
        }
        NSWorkspace.shared.open(url)
    }

    func availableProducts() async -> [SubscriptionProduct] {
        let plans: [SubscriptionPlan] = [.lifetime, .yearly, .monthly]
        return plans.compactMap { plan in
            guard let price = config.displayPrices[plan.rawValue] else { return nil }
            let offersTrial = plan != .lifetime && config.trialDurationDays > 0
            return SubscriptionProduct(
                id: productID(for: plan),
                plan: plan,
                localizedPrice: price,
                localizedPeriod: period(for: plan),
                hasFreeTrial: offersTrial,
                trialDuration: offersTrial ? "\(config.trialDurationDays) days" : nil
            )
        }
    }

    // MARK: - Redemption callback

    /// Routed from `AppDelegate.application(_:open:)`. A redeemed link is not
    /// itself a grant — access follows `status.hasAccess`.
    func handleCallbackURL(_ url: URL) async {
        guard let billing, billing.handlesCallbackURL(url) else { return }

        switch await gateway.redeem(url: url) {
        case .notRedemptionURL:
            break
        case .redeemed(let status) where status.hasAccess:
            logger.info("Redemption granted premium access")
        case .redeemed:
            logger.warning("Link redeemed, but not for the configured entitlement")
        case .failed(let reason):
            logger.error("Redemption failed: \(String(describing: reason), privacy: .public)")
        }
    }

    // MARK: - Plan metadata

    private func productID(for plan: SubscriptionPlan) -> String {
        switch plan {
        case .lifetime: config.lifetimeProductID
        case .yearly: config.yearlyProductID
        case .monthly: config.monthlyProductID
        }
    }

    private func period(for plan: SubscriptionPlan) -> String {
        switch plan {
        case .lifetime: "forever"
        case .yearly: "year"
        case .monthly: "month"
        }
    }
}
