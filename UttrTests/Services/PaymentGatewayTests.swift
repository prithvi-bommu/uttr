import Foundation
import Testing
@testable import Uttr

@Suite("MockPaymentGateway")
struct PaymentGatewayTests {

    // MARK: - Purchase flow

    @Test("purchase returns configured result")
    @MainActor
    func purchaseReturnsResult() async throws {
        let gateway = MockPaymentGateway()
        gateway.purchaseResult = .success

        let product = SubscriptionProduct(
            id: "monthly", plan: .monthly,
            localizedPrice: "$5.99", localizedPeriod: "month",
            hasFreeTrial: true, trialDuration: "3 days"
        )
        let result = try await gateway.purchase(product)
        #expect(result == .success)
        #expect(gateway.purchasedProducts.count == 1)
        #expect(gateway.purchasedProducts[0].id == "monthly")
    }

    @Test("purchase propagates error")
    @MainActor
    func purchaseThrows() async throws {
        let gateway = MockPaymentGateway()
        gateway.purchaseError = .productNotFound

        let product = SubscriptionProduct(
            id: "unknown", plan: .monthly,
            localizedPrice: "$5.99", localizedPeriod: "month",
            hasFreeTrial: false, trialDuration: nil
        )
        await #expect(throws: PaymentError.self) {
            try await gateway.purchase(product)
        }
    }

    @Test("cancelled purchase returns cancelled")
    @MainActor
    func purchaseCancelled() async throws {
        let gateway = MockPaymentGateway()
        gateway.purchaseResult = .cancelled

        let product = SubscriptionProduct(
            id: "annual", plan: .annual,
            localizedPrice: "$39.99", localizedPeriod: "year",
            hasFreeTrial: true, trialDuration: "3 days"
        )
        let result = try await gateway.purchase(product)
        #expect(result == .cancelled)
    }

    // MARK: - Restore

    @Test("restore calls through")
    @MainActor
    func restorePurchases() async throws {
        let gateway = MockPaymentGateway()
        try await gateway.restorePurchases()
        #expect(gateway.restoreCalled)
    }

    @Test("restore propagates error")
    @MainActor
    func restoreThrows() async throws {
        let gateway = MockPaymentGateway()
        gateway.restoreError = .networkError

        await #expect(throws: PaymentError.self) {
            try await gateway.restorePurchases()
        }
    }

    // MARK: - Available products

    @Test("available products returns configured list")
    @MainActor
    func availableProducts() async {
        let gateway = MockPaymentGateway()
        gateway.productsToReturn = [
            SubscriptionProduct(
                id: "weekly", plan: .weekly, localizedPrice: "$2.99",
                localizedPeriod: "week", hasFreeTrial: true, trialDuration: "3 days"
            ),
            SubscriptionProduct(
                id: "monthly", plan: .monthly, localizedPrice: "$5.99",
                localizedPeriod: "month", hasFreeTrial: true, trialDuration: "3 days"
            ),
        ]
        let products = await gateway.availableProducts()
        #expect(products.count == 2)
        #expect(products[0].plan == .weekly)
    }

    // MARK: - Feature gating logic

    @Test("free user cannot access premium features")
    @MainActor
    func freeUserGated() {
        let gateway = MockPaymentGateway()
        gateway.subscriptionStatus = .free
        #expect(!gateway.subscriptionStatus.hasPremiumAccess)
    }

    @Test("subscribed user can access premium features")
    @MainActor
    func subscribedUserHasAccess() {
        let gateway = MockPaymentGateway()
        gateway.subscriptionStatus = .subscribed(
            plan: .monthly, expiresAt: Date().addingTimeInterval(86400), willRenew: true
        )
        #expect(gateway.subscriptionStatus.hasPremiumAccess)
    }

    @Test("lifetime user can access premium features")
    @MainActor
    func lifetimeUserHasAccess() {
        let gateway = MockPaymentGateway()
        gateway.subscriptionStatus = .lifetime
        #expect(gateway.subscriptionStatus.hasPremiumAccess)
    }

    @Test("expired user cannot access premium features")
    @MainActor
    func expiredUserGated() {
        let gateway = MockPaymentGateway()
        gateway.subscriptionStatus = .expired(plan: .annual, expiredAt: Date())
        #expect(!gateway.subscriptionStatus.hasPremiumAccess)
    }

    @Test("trial user can access premium features")
    @MainActor
    func trialUserHasAccess() {
        let gateway = MockPaymentGateway()
        gateway.subscriptionStatus = .trial(expiresAt: Date().addingTimeInterval(86400))
        #expect(gateway.subscriptionStatus.hasPremiumAccess)
    }

    @Test("grace period user can access premium features")
    @MainActor
    func graceUserHasAccess() {
        let gateway = MockPaymentGateway()
        gateway.subscriptionStatus = .grace(plan: .monthly, expiresAt: Date().addingTimeInterval(86400))
        #expect(gateway.subscriptionStatus.hasPremiumAccess)
    }

    @Test("premium gate follows subscription access")
    @MainActor
    func premiumGateAccess() {
        let gateway = MockPaymentGateway()
        let future = Date(timeIntervalSince1970: 1_700_000_001)

        gateway.subscriptionStatus = .free
        #expect(!gateway.subscriptionStatus.hasPremiumAccess)
        gateway.subscriptionStatus = .expired(plan: .monthly, expiredAt: future)
        #expect(!gateway.subscriptionStatus.hasPremiumAccess)

        gateway.subscriptionStatus = .trial(expiresAt: future)
        #expect(gateway.subscriptionStatus.hasPremiumAccess)
        gateway.subscriptionStatus = .subscribed(plan: .monthly, expiresAt: future, willRenew: true)
        #expect(gateway.subscriptionStatus.hasPremiumAccess)
        gateway.subscriptionStatus = .grace(plan: .annual, expiresAt: future)
        #expect(gateway.subscriptionStatus.hasPremiumAccess)
        gateway.subscriptionStatus = .lifetime
        #expect(gateway.subscriptionStatus.hasPremiumAccess)
    }

    // MARK: - Status transitions

    @Test("status can transition from free to subscribed")
    @MainActor
    func freeToSubscribed() {
        let gateway = MockPaymentGateway()
        #expect(gateway.subscriptionStatus == .free)
        #expect(!gateway.subscriptionStatus.hasPremiumAccess)

        gateway.subscriptionStatus = .subscribed(
            plan: .annual, expiresAt: Date().addingTimeInterval(86400), willRenew: true
        )
        #expect(gateway.subscriptionStatus.hasPremiumAccess)
    }

    @Test("status can transition from subscribed to expired")
    @MainActor
    func subscribedToExpired() {
        let gateway = MockPaymentGateway()
        gateway.subscriptionStatus = .subscribed(plan: .monthly, expiresAt: Date(), willRenew: false)
        #expect(gateway.subscriptionStatus.hasPremiumAccess)

        gateway.subscriptionStatus = .expired(plan: .monthly, expiredAt: Date())
        #expect(!gateway.subscriptionStatus.hasPremiumAccess)
    }
}
