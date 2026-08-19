import Foundation
import Testing
@testable import Uttr

@Suite("PricingConfig")
struct PricingConfigTests {

    @Test("default config has expected product IDs")
    func defaultProductIDs() {
        let config = PricingConfig()
        #expect(config.lifetimeProductID == "lifetime")
        #expect(config.yearlyProductID == "yearly")
        #expect(config.monthlyProductID == "monthly")
    }

    @Test("default trial duration is 3 days")
    func defaultTrialDuration() {
        #expect(PricingConfig().trialDurationDays == 3)
    }

    @Test("config decodes from JSON")
    func decodesFromJSON() throws {
        let json = """
        {
            "revenueCatAPIKey": "test_abc123",
            "lifetimeProductID": "lifetime",
            "yearlyProductID": "yearly",
            "monthlyProductID": "monthly",
            "trialDurationDays": 7,
            "entitlementID": "Pro"
        }
        """
        let config = try JSONDecoder().decode(PricingConfig.self, from: Data(json.utf8))
        #expect(config.revenueCatAPIKey == "test_abc123")
        #expect(config.lifetimeProductID == "lifetime")
        #expect(config.trialDurationDays == 7)
        #expect(config.entitlementID == "Pro")
    }

    @Test("config round-trips through JSON")
    func roundTrip() throws {
        var config = PricingConfig()
        config.revenueCatAPIKey = "appl_xyz"
        config.entitlementID = "Premium"
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(PricingConfig.self, from: data)
        #expect(decoded.revenueCatAPIKey == config.revenueCatAPIKey)
        #expect(decoded.entitlementID == config.entitlementID)
        #expect(decoded.lifetimeProductID == config.lifetimeProductID)
    }

    @Test("bundled PricingConfig.json loads successfully")
    func bundledConfigLoads() {
        let config = PricingConfigLoader.load()
        #expect(!config.revenueCatAPIKey.isEmpty)
        #expect(!config.entitlementID.isEmpty)
    }

    @Test("missing JSON values retain safe defaults")
    func missingValuesUseDefaults() {
        let config = PricingConfigLoader.load(data: Data("{}".utf8))
        #expect(config.entitlementID == "uttr_pro")
        #expect(config.monthlyProductID == "monthly")
        #expect(config.trialDurationDays == 3)
    }

    @Test("malformed JSON falls back without throwing")
    func malformedJSONFallsBack() {
        let config = PricingConfigLoader.load(data: Data("not json".utf8))
        #expect(config.revenueCatAPIKey.isEmpty)
        #expect(config.entitlementID == "uttr_pro")
    }
}
