import Foundation

enum SubscriptionStatus: Codable, Equatable, Sendable {
    case free
    case trial(expiresAt: Date)
    case subscribed(plan: SubscriptionPlan, expiresAt: Date, willRenew: Bool)
    case expired(plan: SubscriptionPlan, expiredAt: Date)
    case grace(plan: SubscriptionPlan, expiresAt: Date)
    case lifetime

    var hasPremiumAccess: Bool {
        switch self {
        case .free, .expired: false
        case .trial, .subscribed, .grace, .lifetime: true
        }
    }

    var displayName: String {
        switch self {
        case .free: "Free"
        case .trial: "Premium Trial"
        case .subscribed: "Premium"
        case .expired: "Expired"
        case .grace: "Premium (Grace Period)"
        case .lifetime: "Lifetime Premium"
        }
    }

    var expirationDate: Date? {
        switch self {
        case .trial(let date): date
        case .subscribed(_, let date, _): date
        case .expired(_, let date): date
        case .grace(_, let date): date
        case .free, .lifetime: nil
        }
    }

    /// Downgrades a cached status whose expiry has passed before granting
    /// offline premium access. Live RevenueCat statuses are authoritative.
    func resolved(asOf now: Date = Date()) -> SubscriptionStatus {
        switch self {
        case .free, .expired, .lifetime:
            return self
        case .trial(let expiresAt):
            return expiresAt > now ? self : .free
        case .subscribed(let plan, let expiresAt, _), .grace(let plan, let expiresAt):
            return expiresAt > now ? self : .expired(plan: plan, expiredAt: expiresAt)
        }
    }
}

enum SubscriptionPlan: String, Codable, Equatable, Sendable {
    case weekly
    case monthly
    case annual

    var displayName: String {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .annual: "Annual"
        }
    }
}

struct SubscriptionProduct: Sendable, Identifiable {
    let id: String
    let plan: SubscriptionPlan
    let localizedPrice: String
    let localizedPeriod: String
    let hasFreeTrial: Bool
    let trialDuration: String?
}

enum PurchaseResult: Sendable {
    case success
    case cancelled
    case pending
}

enum PaymentError: LocalizedError, Sendable {
    case productNotFound
    case purchaseFailed(String)
    case networkError

    var errorDescription: String? {
        switch self {
        case .productNotFound: "The requested product could not be found."
        case .purchaseFailed(let reason): "Purchase failed: \(reason)"
        case .networkError: "A network error occurred. Please try again."
        }
    }
}
