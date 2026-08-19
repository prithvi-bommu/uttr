import Foundation

struct PricingConfig: Codable, Sendable {
    var revenueCatAPIKey: String = ""
    var lifetimeProductID: String = "lifetime"
    var yearlyProductID: String = "yearly"
    var monthlyProductID: String = "monthly"
    var trialDurationDays: Int = 3
    var entitlementID: String = "uttr_pro"

    init(
        revenueCatAPIKey: String = "",
        lifetimeProductID: String = "lifetime",
        yearlyProductID: String = "yearly",
        monthlyProductID: String = "monthly",
        trialDurationDays: Int = 3,
        entitlementID: String = "uttr_pro"
    ) {
        self.revenueCatAPIKey = revenueCatAPIKey
        self.lifetimeProductID = lifetimeProductID
        self.yearlyProductID = yearlyProductID
        self.monthlyProductID = monthlyProductID
        self.trialDurationDays = trialDurationDays
        self.entitlementID = entitlementID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revenueCatAPIKey = try container.decodeIfPresent(String.self, forKey: .revenueCatAPIKey) ?? ""
        lifetimeProductID = try container.decodeIfPresent(String.self, forKey: .lifetimeProductID) ?? "lifetime"
        yearlyProductID = try container.decodeIfPresent(String.self, forKey: .yearlyProductID) ?? "yearly"
        monthlyProductID = try container.decodeIfPresent(String.self, forKey: .monthlyProductID) ?? "monthly"
        trialDurationDays = try container.decodeIfPresent(Int.self, forKey: .trialDurationDays) ?? 3
        entitlementID = try container.decodeIfPresent(String.self, forKey: .entitlementID) ?? "uttr_pro"
    }
}

enum PricingConfigLoader {
    static func load() -> PricingConfig {
        guard let url = Bundle.main.url(forResource: "PricingConfig", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return PricingConfig()
        }
        return load(data: data)
    }

    static func load(data: Data) -> PricingConfig {
        (try? JSONDecoder().decode(PricingConfig.self, from: data)) ?? PricingConfig()
    }
}
