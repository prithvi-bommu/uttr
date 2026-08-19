import Foundation
import OSLog
import RevenueCat

@MainActor @Observable
final class RevenueCatGateway: PaymentGateway {
    private(set) var subscriptionStatus: SubscriptionStatus = .free
    private let pricingConfig: PricingConfig
    private let logger = Logger(subsystem: "com.uttr.app", category: "payment")
    private var listenerTask: Task<Void, Never>?

    private static let cachedStatusKey = "com.uttr.cachedSubscriptionStatus"

    init(pricingConfig: PricingConfig) {
        self.pricingConfig = pricingConfig
        loadCachedStatus()
    }

    func configure() async {
        guard !pricingConfig.revenueCatAPIKey.isEmpty,
              pricingConfig.revenueCatAPIKey != "YOUR_REVENUECAT_PUBLIC_KEY" else {
            logger.warning("RevenueCat API key not configured — payment gateway inactive")
            return
        }

        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: pricingConfig.revenueCatAPIKey)

        listenerTask = Task { [weak self] in
            for await customerInfo in Purchases.shared.customerInfoStream {
                guard let self else { return }
                let status = self.mapCustomerInfo(customerInfo)
                self.subscriptionStatus = status
                self.cacheStatus(status)
                self.logger.info("Subscription status updated: \(status.displayName, privacy: .public)")
            }
        }

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            let status = mapCustomerInfo(customerInfo)
            subscriptionStatus = status
            cacheStatus(status)
        } catch {
            logger.error("Failed to fetch initial customer info: \(error.localizedDescription, privacy: .public)")
        }
    }

    func purchase(_ product: SubscriptionProduct) async throws -> PurchaseResult {
        let offerings = try await Purchases.shared.offerings()
        guard let offering = offerings.current else {
            throw PaymentError.productNotFound
        }

        guard let package = offering.availablePackages.first(where: {
            $0.storeProduct.productIdentifier == product.id
        }) else {
            throw PaymentError.productNotFound
        }

        do {
            let (_, customerInfo, userCancelled) = try await Purchases.shared.purchase(package: package)
            if userCancelled {
                return .cancelled
            }
            let status = mapCustomerInfo(customerInfo)
            subscriptionStatus = status
            cacheStatus(status)
            return status.hasPremiumAccess ? .success : .pending
        } catch {
            throw PaymentError.purchaseFailed(error.localizedDescription)
        }
    }

    func restorePurchases() async throws {
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            let status = mapCustomerInfo(customerInfo)
            subscriptionStatus = status
            cacheStatus(status)
        } catch {
            throw PaymentError.networkError
        }
    }

    func availableProducts() async -> [SubscriptionProduct] {
        do {
            let offerings = try await Purchases.shared.offerings()
            guard let offering = offerings.current else { return [] }
            return offering.availablePackages.compactMap { package in
                let storeProduct = package.storeProduct
                guard let plan = planForProductID(storeProduct.productIdentifier) else {
                    return nil
                }

                var trialDuration: String?
                let hasIntro = storeProduct.introductoryDiscount != nil
                if let intro = storeProduct.introductoryDiscount,
                   intro.paymentMode == .freeTrial {
                    trialDuration = intro.subscriptionPeriod.durationTitle
                }

                let period: String
                switch plan {
                case .lifetime: period = "forever"
                case .yearly: period = "year"
                case .monthly: period = "month"
                }

                return SubscriptionProduct(
                    id: storeProduct.productIdentifier,
                    plan: plan,
                    localizedPrice: storeProduct.localizedPriceString,
                    localizedPeriod: period,
                    hasFreeTrial: hasIntro,
                    trialDuration: trialDuration
                )
            }
            .sorted { sortOrder($0.plan) < sortOrder($1.plan) }
        } catch {
            logger.error("Failed to fetch offerings: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func sortOrder(_ plan: SubscriptionPlan) -> Int {
        switch plan {
        case .lifetime: 0
        case .yearly: 1
        case .monthly: 2
        }
    }

    // MARK: - Customer info mapping

    private func mapCustomerInfo(_ info: CustomerInfo) -> SubscriptionStatus {
        let entitlementID = pricingConfig.entitlementID

        if info.nonSubscriptions.contains(where: {
            $0.productIdentifier == pricingConfig.lifetimeProductID
        }) {
            return .lifetime
        }

        guard let entitlement = info.entitlements[entitlementID],
              entitlement.isActive else {
            if let entitlement = info.entitlements[entitlementID],
               let expiration = entitlement.expirationDate {
                let productID = entitlement.productIdentifier
                let plan = planForProductID(productID) ?? .monthly
                return .expired(plan: plan, expiredAt: expiration)
            }
            return .free
        }

        let productID = entitlement.productIdentifier
        let plan = planForProductID(productID) ?? .monthly
        let expiresAt = entitlement.expirationDate ?? .distantFuture

        if plan == .lifetime || entitlement.expirationDate == nil {
            return .lifetime
        }

        let willRenew = entitlement.willRenew

        if entitlement.periodType == .trial {
            return .trial(expiresAt: expiresAt)
        }

        if entitlement.billingIssueDetectedAt != nil {
            return .grace(plan: plan, expiresAt: expiresAt)
        }

        return .subscribed(plan: plan, expiresAt: expiresAt, willRenew: willRenew)
    }

    private func planForProductID(_ productID: String) -> SubscriptionPlan? {
        switch productID {
        case pricingConfig.lifetimeProductID: .lifetime
        case pricingConfig.yearlyProductID: .yearly
        case pricingConfig.monthlyProductID: .monthly
        default: nil
        }
    }

    // MARK: - Cache

    private func loadCachedStatus() {
        guard let data = UserDefaults.standard.data(forKey: Self.cachedStatusKey),
              let status = try? JSONDecoder().decode(SubscriptionStatus.self, from: data) else {
            return
        }
        subscriptionStatus = status.resolved()
    }

    private func cacheStatus(_ status: SubscriptionStatus) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        UserDefaults.standard.set(data, forKey: Self.cachedStatusKey)
    }
}

private extension SubscriptionPeriod {
    var durationTitle: String {
        switch unit {
        case .day: value == 1 ? "1 day" : "\(value) days"
        case .week: value == 1 ? "1 week" : "\(value) weeks"
        case .month: value == 1 ? "1 month" : "\(value) months"
        case .year: value == 1 ? "1 year" : "\(value) years"
        @unknown default: "\(value) \(unit)"
        }
    }
}
