import EntitlementKitCore
import Foundation
import Testing
@testable import Uttr

/// Pins the reason `EntitlementKitPaymentGateway` gives its status cache its own
/// UserDefaults key instead of reusing the StoreKit gateway's
/// `com.uttr.cachedSubscriptionStatus`. The two payloads look
/// interchangeable — same six cases, same offline-expiry rules — but the
/// associated-value labels differ, so a reused key would decode to `nil` and
/// silently downgrade an offline subscriber to `.free`.
///
/// If `SubscriptionStatus` is ever reshaped to match, these tests fail and the
/// keys can be merged behind a real migration.
@Suite("Entitlement cache compatibility")
struct EntitlementCacheCompatibilityTests {

    private let expiry = Date(timeIntervalSince1970: 1_900_000_000)

    @Test("a legacy subscribed cache cannot be read as an EntitlementStatus")
    func subscribedIsIncompatible() throws {
        let legacy = try JSONEncoder().encode(
            SubscriptionStatus.subscribed(plan: .yearly, expiresAt: expiry, willRenew: true)
        )
        #expect((try? JSONDecoder().decode(EntitlementStatus.self, from: legacy)) == nil)
    }

    @Test("a legacy grace cache cannot be read as an EntitlementStatus")
    func graceIsIncompatible() throws {
        let legacy = try JSONEncoder().encode(
            SubscriptionStatus.grace(plan: .monthly, expiresAt: expiry)
        )
        #expect((try? JSONDecoder().decode(EntitlementStatus.self, from: legacy)) == nil)
    }
}
