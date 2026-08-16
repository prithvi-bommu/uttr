import Foundation

struct PricingConfig: Codable, Sendable {
    var revenueCatAPIKey: String = ""
    var lifetimeProductID: String = "lifetime"
    var yearlyProductID: String = "yearly"
    var monthlyProductID: String = "monthly"
    var trialDurationDays: Int = 3
    var entitlementID: String = "Create an app called Uttr Pro"
}

enum PricingConfigLoader {
    static func load() -> PricingConfig {
        guard let url = Bundle.main.url(forResource: "PricingConfig", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(PricingConfig.self, from: data) else {
            return PricingConfig()
        }
        return config
    }
}
