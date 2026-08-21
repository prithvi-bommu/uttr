import Foundation
import Testing
@testable import Uttr

/// Redemption must route on the callback scheme alone. Gating it on checkout
/// configuration silently drops real redemption links in any build where the
/// URL scheme is registered but `webPurchaseLink` is still empty — the state
/// every pre-launch build ships in.
///
/// These tests drive the real `handleCallbackURL(_:)` rather than a predicate,
/// so re-coupling routing to checkout config fails them. That is safe without
/// configuring the RevenueCat SDK: `redeem(url:)` parses the URL first, and a
/// URL whose host is not `redeem_web_purchase` returns before any SDK call.
@Suite("EntitlementKitPaymentGateway callback routing")
struct EntitlementKitPaymentGatewayTests {

    /// On our scheme, but not a redemption link — reaches `redeem(url:)` and
    /// returns without touching `Purchases.shared`.
    private func nonRedemptionCallback() throws -> URL {
        try #require(URL(string: "rc-test://some-other-deep-link"))
    }

    @Test("a matching scheme reaches redemption with no purchase link configured")
    @MainActor
    func matchingSchemeReachesRedemption() async throws {
        let config = PricingConfig(callbackScheme: "rc-test")
        #expect(config.webPurchaseURL == nil, "checkout must be unconfigured or this test proves nothing")

        let gateway = EntitlementKitPaymentGateway(pricingConfig: config)
        let url = try nonRedemptionCallback()
        let outcome = await gateway.handleCallbackURL(url)

        // Anything that re-couples routing to checkout configuration would
        // short-circuit to .notForThisApp here instead of reaching redemption.
        #expect(outcome == .notRedemptionLink)
    }

    @Test("scheme matching is case-insensitive")
    @MainActor
    func schemeMatchingIsCaseInsensitive() async throws {
        let gateway = EntitlementKitPaymentGateway(
            pricingConfig: PricingConfig(callbackScheme: "rc-test")
        )
        let url = try #require(URL(string: "RC-TEST://some-other-deep-link"))
        let outcome = await gateway.handleCallbackURL(url)

        #expect(outcome == .notRedemptionLink)
    }

    @Test("URLs on another scheme are never routed")
    @MainActor
    func foreignSchemesIgnored() async throws {
        let gateway = EntitlementKitPaymentGateway(
            pricingConfig: PricingConfig(callbackScheme: "rc-test")
        )

        let otherScheme = try #require(URL(string: "uttr://redeem_web_purchase?redemption_token=abc"))
        let schemeOutcome = await gateway.handleCallbackURL(otherScheme)
        #expect(schemeOutcome == .notForThisApp)

        let web = try #require(URL(string: "https://example.com/redeem"))
        let webOutcome = await gateway.handleCallbackURL(web)
        #expect(webOutcome == .notForThisApp)
    }
}
