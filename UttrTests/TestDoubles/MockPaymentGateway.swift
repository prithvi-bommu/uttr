import Foundation
@testable import Uttr

@MainActor
final class MockPaymentGateway: PaymentGateway {
    var subscriptionStatus: SubscriptionStatus = .free
    var productsToReturn: [SubscriptionProduct] = []
    var purchaseResult: PurchaseResult = .success
    var purchaseError: PaymentError?
    var restoreError: PaymentError?
    var configureCalled = false
    var purchasedProducts: [SubscriptionProduct] = []
    var restoreCalled = false

    func configure() async {
        configureCalled = true
    }

    func purchase(_ product: SubscriptionProduct) async throws -> PurchaseResult {
        purchasedProducts.append(product)
        if let error = purchaseError {
            throw error
        }
        return purchaseResult
    }

    func restorePurchases() async throws {
        restoreCalled = true
        if let error = restoreError {
            throw error
        }
    }

    func availableProducts() async -> [SubscriptionProduct] {
        productsToReturn
    }
}
