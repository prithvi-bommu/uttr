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

    /// Deliberately not the StoreKit gateway's `com.uttr.cachedSubscriptionStatus`.
    /// That key holds `SubscriptionStatus` JSON, which is shaped differently from
    /// the `EntitlementStatus` JSON written here: `.subscribed`/`.grace` encode a
    /// `plan` key rather than `planID`, so reusing the key would fail to decode
    /// and silently downgrade an offline subscriber to `.free`. The stale value is
    /// left in place so a real migration remains possible.
    private static let cachedStatusKey = "com.uttr.cachedEntitlementStatus"

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
            // Uttr sells no lifetime plan, so no product ID maps to it here. The
            // adapter still treats an active entitlement with no expiration date
            // as lifetime (e.g. a dashboard-granted comp), and SubscriptionStatus
            // keeps that case for exactly that fallback.
            lifetimePlanIDs: [],
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
        // Best value first, shortest commitment last.
        let plans: [SubscriptionPlan] = [.annual, .monthly, .weekly]
        return plans.compactMap { plan in
            guard let price = config.displayPrices[plan.rawValue] else { return nil }
            let offersTrial = config.trialDurationDays > 0
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

    /// Whether an incoming URL belongs to this app's registered callback scheme.
    ///
    /// Matches `WebBillingConfiguration.handlesCallbackURL(_:)` semantics, but
    /// reads the scheme straight off `config` so routing does not depend on
    /// checkout being configured.
    private func handlesCallbackURL(_ url: URL) -> Bool {
        url.scheme?.caseInsensitiveCompare(config.callbackScheme) == .orderedSame
    }

    /// Routed from `AppDelegate.application(_:open:)`. A redeemed link is not
    /// itself a grant — access follows `status.hasAccess`.
    ///
    /// Deliberately independent of `billing`. Redemption needs only the callback
    /// scheme: `redeem(url:)` never reads the purchase link. Gating this on
    /// `billing` silently dropped every real redemption link in any build with
    /// the URL scheme registered but `webPurchaseLink` still empty.
    func handleCallbackURL(_ url: URL) async -> RedemptionOutcome {
        guard handlesCallbackURL(url) else { return .notForThisApp }

        switch await gateway.redeem(url: url) {
        case .notRedemptionURL:
            logger.warning("Callback URL matched our scheme but was not a redemption link")
            return .notRedemptionLink
        case .redeemed(let status) where status.hasAccess:
            logger.info("Redemption granted premium access")
            return .granted
        case .redeemed:
            logger.warning("Link redeemed, but not for the configured entitlement")
            return .redeemedWithoutAccess
        case .failed(let reason):
            logger.error("Redemption failed: \(String(describing: reason), privacy: .public)")
            return .failed
        }
    }

    // MARK: - Plan metadata

    private func productID(for plan: SubscriptionPlan) -> String {
        switch plan {
        case .weekly: config.weeklyProductID
        case .monthly: config.monthlyProductID
        case .annual: config.annualProductID
        }
    }

    private func period(for plan: SubscriptionPlan) -> String {
        switch plan {
        case .weekly: "week"
        case .monthly: "month"
        case .annual: "year"
        }
    }
}
