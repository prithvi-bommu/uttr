import Foundation

@MainActor
protocol PaymentGateway: AnyObject {
    var subscriptionStatus: SubscriptionStatus { get }
    func configure() async
    func purchase(_ product: SubscriptionProduct) async throws -> PurchaseResult
    func restorePurchases() async throws
    func availableProducts() async -> [SubscriptionProduct]
}
