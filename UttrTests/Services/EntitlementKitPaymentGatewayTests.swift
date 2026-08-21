import Foundation
import Testing
@testable import Uttr

/// Redemption must route on the callback scheme alone. Gating it on checkout
/// configuration silently drops real redemption links in any build where the
/// URL scheme is registered but `webPurchaseLink` is still empty — the state
/// every pre-launch build ships in.
@Suite("EntitlementKitPaymentGateway callback routing")
struct EntitlementKitPaymentGatewayTests {

    @Test("routes matching callback URLs with no purchase link configured")
    @MainActor
    func routesCallbackWithoutPurchaseLink() throws {
        let config = PricingConfig(callbackScheme: "rc-test")
        #expect(config.webPurchaseURL == nil, "checkout must be unconfigured or this test proves nothing")

        let gateway = EntitlementKitPaymentGateway(pricingConfig: config)

        let exact = try #require(URL(string: "rc-test://redeem?token=abc"))
        #expect(gateway.handlesCallbackURL(exact))

        let uppercased = try #require(URL(string: "RC-TEST://redeem"))
        #expect(gateway.handlesCallbackURL(uppercased))
    }

    @Test("ignores URLs belonging to other schemes")
    @MainActor
    func ignoresForeignSchemes() throws {
        let gateway = EntitlementKitPaymentGateway(
            pricingConfig: PricingConfig(callbackScheme: "rc-test")
        )

        let otherScheme = try #require(URL(string: "uttr://redeem"))
        #expect(!gateway.handlesCallbackURL(otherScheme))

        let web = try #require(URL(string: "https://example.com/redeem"))
        #expect(!gateway.handlesCallbackURL(web))
    }
}
