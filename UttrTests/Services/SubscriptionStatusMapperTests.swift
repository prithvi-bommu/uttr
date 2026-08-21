import EntitlementKitCore
import Foundation
import Testing
@testable import Uttr

@Suite("SubscriptionStatusMapper")
struct SubscriptionStatusMapperTests {

    private var mapper: SubscriptionStatusMapper {
        SubscriptionStatusMapper(config: PricingConfig())
    }

    @Test("free maps to free")
    func mapsFree() {
        #expect(mapper.subscriptionStatus(from: .free) == .free)
    }

    @Test("trial preserves expiry")
    func mapsTrial() {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(mapper.subscriptionStatus(from: .trial(expiresAt: expiry)) == .trial(expiresAt: expiry))
    }

    @Test("subscribed preserves plan, expiry, and renewal")
    func mapsSubscribed() {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        let mapped = mapper.subscriptionStatus(
            from: .subscribed(planID: "annual", expiresAt: expiry, willRenew: false)
        )
        #expect(mapped == .subscribed(plan: .annual, expiresAt: expiry, willRenew: false))
    }

    @Test("expired preserves plan and date")
    func mapsExpired() {
        let expiry = Date(timeIntervalSince1970: 1_700_000_000)
        let mapped = mapper.subscriptionStatus(from: .expired(planID: "monthly", expiredAt: expiry))
        #expect(mapped == .expired(plan: .monthly, expiredAt: expiry))
    }

    @Test("grace preserves plan and expiry")
    func mapsGrace() {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        let mapped = mapper.subscriptionStatus(from: .grace(planID: "annual", expiresAt: expiry))
        #expect(mapped == .grace(plan: .annual, expiresAt: expiry))
    }

    /// EntitlementKit's `.lifetime` status is not tied to Uttr's plan catalog —
    /// it fires for any active entitlement with no expiration date (e.g. a
    /// promotional grant), independent of whether Uttr sells a lifetime plan.
    @Test("lifetime maps to lifetime regardless of plan ID")
    func mapsLifetime() {
        #expect(mapper.subscriptionStatus(from: .lifetime(planID: "promo")) == .lifetime)
        #expect(mapper.subscriptionStatus(from: .lifetime(planID: nil)) == .lifetime)
    }

    @Test("known product IDs resolve to their plans")
    func resolvesKnownPlans() {
        #expect(mapper.plan(for: "weekly") == .weekly)
        #expect(mapper.plan(for: "monthly") == .monthly)
        #expect(mapper.plan(for: "annual") == .annual)
    }

    @Test("unknown product ID falls back to monthly")
    func fallsBackToMonthly() {
        #expect(mapper.plan(for: "com.example.unknown") == .monthly)
    }

    @Test("mapped statuses preserve access semantics")
    func preservesAccess() {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(mapper.subscriptionStatus(from: .free).hasPremiumAccess == false)
        #expect(mapper.subscriptionStatus(from: .expired(planID: "annual", expiredAt: expiry))
            .hasPremiumAccess == false)
        #expect(mapper.subscriptionStatus(from: .lifetime(planID: nil)).hasPremiumAccess == true)
        #expect(mapper.subscriptionStatus(from: .grace(planID: "annual", expiresAt: expiry))
            .hasPremiumAccess == true)
    }
}
