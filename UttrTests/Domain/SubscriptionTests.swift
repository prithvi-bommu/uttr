import Foundation
import Testing
@testable import Uttr

@Suite("SubscriptionStatus")
struct SubscriptionStatusTests {

    // MARK: - Premium access

    @Test("free has no premium access")
    func freeNoPremium() {
        #expect(!SubscriptionStatus.free.hasPremiumAccess)
    }

    @Test("expired has no premium access")
    func expiredNoPremium() {
        let status = SubscriptionStatus.expired(plan: .monthly, expiredAt: Date())
        #expect(!status.hasPremiumAccess)
    }

    @Test("trial has premium access")
    func trialHasPremium() {
        let status = SubscriptionStatus.trial(expiresAt: Date().addingTimeInterval(3600))
        #expect(status.hasPremiumAccess)
    }

    @Test("subscribed has premium access")
    func subscribedHasPremium() {
        let status = SubscriptionStatus.subscribed(
            plan: .monthly, expiresAt: Date().addingTimeInterval(3600), willRenew: true
        )
        #expect(status.hasPremiumAccess)
    }

    @Test("grace period has premium access")
    func graceHasPremium() {
        let status = SubscriptionStatus.grace(plan: .yearly, expiresAt: Date().addingTimeInterval(3600))
        #expect(status.hasPremiumAccess)
    }

    @Test("lifetime has premium access")
    func lifetimeHasPremium() {
        #expect(SubscriptionStatus.lifetime.hasPremiumAccess)
    }

    // MARK: - Display names

    @Test("display names are human-readable", arguments: [
        (SubscriptionStatus.free, "Free"),
        (.lifetime, "Lifetime Premium"),
        (.trial(expiresAt: Date()), "Premium Trial"),
        (.subscribed(plan: .monthly, expiresAt: Date(), willRenew: true), "Premium"),
        (.expired(plan: .monthly, expiredAt: Date()), "Expired"),
        (.grace(plan: .monthly, expiresAt: Date()), "Premium (Grace Period)"),
    ])
    func displayNames(status: SubscriptionStatus, expected: String) {
        #expect(status.displayName == expected)
    }

    // MARK: - Expiration date

    @Test("free has no expiration date")
    func freeNoExpiration() {
        #expect(SubscriptionStatus.free.expirationDate == nil)
    }

    @Test("lifetime has no expiration date")
    func lifetimeNoExpiration() {
        #expect(SubscriptionStatus.lifetime.expirationDate == nil)
    }

    @Test("trial expiration date is returned")
    func trialExpiration() {
        let date = Date().addingTimeInterval(86400)
        let status = SubscriptionStatus.trial(expiresAt: date)
        #expect(status.expirationDate == date)
    }

    @Test("subscribed expiration date is returned")
    func subscribedExpiration() {
        let date = Date().addingTimeInterval(86400)
        let status = SubscriptionStatus.subscribed(plan: .yearly, expiresAt: date, willRenew: false)
        #expect(status.expirationDate == date)
    }

    // MARK: - Codable round-trip

    @Test("all statuses survive encode/decode", arguments: [
        SubscriptionStatus.free,
        .lifetime,
        .trial(expiresAt: Date(timeIntervalSince1970: 1_700_000_000)),
        .subscribed(plan: .monthly, expiresAt: Date(timeIntervalSince1970: 1_700_000_000), willRenew: true),
        .subscribed(plan: .yearly, expiresAt: Date(timeIntervalSince1970: 1_700_000_000), willRenew: false),
        .expired(plan: .monthly, expiredAt: Date(timeIntervalSince1970: 1_700_000_000)),
        .grace(plan: .yearly, expiresAt: Date(timeIntervalSince1970: 1_700_000_000)),
    ])
    func codableRoundTrip(status: SubscriptionStatus) throws {
        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(SubscriptionStatus.self, from: data)
        #expect(decoded == status)
    }
}

@Suite("SubscriptionPlan")
struct SubscriptionPlanTests {

    @Test("plan display names")
    func displayNames() {
        #expect(SubscriptionPlan.lifetime.displayName == "Lifetime")
        #expect(SubscriptionPlan.yearly.displayName == "Yearly")
        #expect(SubscriptionPlan.monthly.displayName == "Monthly")
    }

    @Test("plans encode to raw values")
    func rawValues() {
        #expect(SubscriptionPlan.lifetime.rawValue == "lifetime")
        #expect(SubscriptionPlan.yearly.rawValue == "yearly")
        #expect(SubscriptionPlan.monthly.rawValue == "monthly")
    }
}

@Suite("PaymentError")
struct PaymentErrorTests {

    @Test("error descriptions are user-facing")
    func errorDescriptions() {
        #expect(PaymentError.productNotFound.errorDescription != nil)
        #expect(PaymentError.networkError.errorDescription != nil)
        #expect(PaymentError.purchaseFailed("card declined").errorDescription?.contains("card declined") == true)
    }
}
