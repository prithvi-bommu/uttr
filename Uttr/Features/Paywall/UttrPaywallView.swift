import SwiftUI

struct UttrPaywallView: View {
    let paymentGateway: any PaymentGateway
    var onDismiss: (() -> Void)?

    @State private var products: [SubscriptionProduct] = []
    @State private var isLoading = true
    @State private var checkoutStarted = false
    @State private var errorMessage: String?

    private var hasPremiumAccess: Bool {
        paymentGateway.subscriptionStatus.hasPremiumAccess
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headline
                planList
                if checkoutStarted {
                    waitingNotice
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                footnote
            }
            .padding(24)
        }
        .frame(minWidth: 440, minHeight: 540)
        .task { await loadProducts() }
        .onChange(of: hasPremiumAccess) { _, unlocked in
            if unlocked { onDismiss?() }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { onDismiss?() }
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Uttr Pro")
                .font(.largeTitle.bold())
            Text("Unlock AI Content mode and Cloud Text Polish.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var planList: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        } else if products.isEmpty {
            Text("Plans are unavailable right now. Please try again later.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 10) {
                ForEach(products) { product in
                    planRow(product)
                }
            }
        }
    }

    private func planRow(_ product: SubscriptionProduct) -> some View {
        Button {
            startCheckout(for: product)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.plan.displayName)
                        .font(.headline)
                    if let trial = product.trialDuration {
                        Text("\(trial) free trial")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.localizedPrice)
                        .font(.headline)
                    Text(product.plan == .lifetime ? "one-time" : "per \(product.localizedPeriod)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
    }

    private var waitingNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Finish checkout in your browser", systemImage: "safari")
                .font(.headline)
            Text("""
                After paying, open the redemption link sent to your billing \
                email. Uttr unlocks as soon as that link is redeemed on this Mac.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footnote: some View {
        Text("Checkout happens in your browser. Uttr never sees your payment details.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func loadProducts() async {
        products = await paymentGateway.availableProducts()
        isLoading = false
    }

    private func startCheckout(for product: SubscriptionProduct) {
        errorMessage = nil
        Task {
            do {
                _ = try await paymentGateway.purchase(product)
                checkoutStarted = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
