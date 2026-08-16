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
}

enum SubscriptionPlan: String, Codable, Equatable, Sendable {
    case lifetime
    case yearly
    case monthly

    var displayName: String {
        switch self {
        case .lifetime: "Lifetime"
        case .yearly: "Yearly"
        case .monthly: "Monthly"
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
