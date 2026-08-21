import Foundation

@MainActor
protocol PaymentGateway: AnyObject {
    var subscriptionStatus: SubscriptionStatus { get }

    /// Where the customer manages an existing subscription. `nil` when the
    /// build has no portal configured.
    var subscriptionManagementURL: URL? { get }

    func configure() async
    func purchase(_ product: SubscriptionProduct) async throws -> PurchaseResult
    func restorePurchases() async throws
    func availableProducts() async -> [SubscriptionProduct]

    /// Handles a custom-scheme URL routed from the app delegate. Checkout runs
    /// in the browser, so entitlements arrive through a redemption callback
    /// rather than a purchase return value.
    ///
    /// Returns the outcome so callers — and tests — can tell a URL that was
    /// never ours from one that was routed and then failed.
    func handleCallbackURL(_ url: URL) async -> RedemptionOutcome
}
