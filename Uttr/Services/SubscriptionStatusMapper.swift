import EntitlementKitCore
import Foundation

/// Translates EntitlementKit's provider-neutral status into Uttr's domain
/// type. Kept out of the gateway so it can be tested without configuring the
/// RevenueCat SDK.
struct SubscriptionStatusMapper: Sendable {
    private let lifetimeProductID: String
    private let yearlyProductID: String
    private let monthlyProductID: String

    init(config: PricingConfig) {
        self.lifetimeProductID = config.lifetimeProductID
        self.yearlyProductID = config.yearlyProductID
        self.monthlyProductID = config.monthlyProductID
    }

    func subscriptionStatus(from status: EntitlementStatus) -> SubscriptionStatus {
        switch status {
        case .free:
            .free
        case .trial(let expiresAt):
            .trial(expiresAt: expiresAt)
        case .subscribed(let planID, let expiresAt, let willRenew):
            .subscribed(plan: plan(for: planID), expiresAt: expiresAt, willRenew: willRenew)
        case .expired(let planID, let expiredAt):
            .expired(plan: plan(for: planID), expiredAt: expiredAt)
        case .grace(let planID, let expiresAt):
            .grace(plan: plan(for: planID), expiresAt: expiresAt)
        case .lifetime:
            .lifetime
        }
    }

    /// Mirrors the fallback the StoreKit gateway used: an unrecognised product
    /// still grants access, it just displays as the monthly plan.
    func plan(for productID: String) -> SubscriptionPlan {
        switch productID {
        case lifetimeProductID: .lifetime
        case yearlyProductID: .yearly
        case monthlyProductID: .monthly
        default: .monthly
        }
    }
}
