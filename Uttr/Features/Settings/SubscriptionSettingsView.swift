import SwiftUI

struct SubscriptionSettingsView: View {
    let paymentGateway: any PaymentGateway
    @State private var showPaywall = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    var body: some View {
        Form {
            Section("Current Plan") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusTitle)
                            .font(.headline)
                        Text(statusSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    statusBadge
                }
            }

            if paymentGateway.subscriptionStatus.hasPremiumAccess {
                Section("Premium Features") {
                    Label("AI Content Writing", systemImage: "wand.and.stars")
                    Label("Cloud Text Polish", systemImage: "sparkles")
                }

                if let date = paymentGateway.subscriptionStatus.expirationDate {
                    Section("Details") {
                        HStack {
                            Text(renewalLabel)
                            Spacer()
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("Manage Subscription") {
                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } else {
                Section {
                    Button("Upgrade to Uttr Pro") {
                        showPaywall = true
                    }
                    .buttonStyle(.borderedProminent)
                }

                Section {
                    Button(isRestoring ? "Restoring..." : "Restore Purchases") {
                        restore()
                    }
                    .disabled(isRestoring)

                    if let restoreMessage {
                        Text(restoreMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showPaywall) {
            UttrPaywallView(
                onDismiss: { showPaywall = false },
                onPurchaseCompleted: { showPaywall = false }
            )
        }
    }

    private var statusTitle: String {
        paymentGateway.subscriptionStatus.displayName
    }

    private var statusSubtitle: String {
        switch paymentGateway.subscriptionStatus {
        case .free:
            "Upgrade to unlock AI Content and Cloud Text Polish"
        case .trial(let expires):
            "Trial ends \(expires.formatted(date: .abbreviated, time: .omitted))"
        case .subscribed(let plan, _, let willRenew):
            "\(plan.displayName) plan\(willRenew ? "" : " — cancels at period end")"
        case .expired:
            "Your subscription has expired"
        case .grace:
            "There's a billing issue — please update your payment method"
        case .lifetime:
            "All premium features unlocked forever"
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if paymentGateway.subscriptionStatus.hasPremiumAccess {
            Text("Active")
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.green.opacity(0.15), in: Capsule())
                .foregroundStyle(.green)
        } else {
            Text("Free")
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(.secondary)
        }
    }

    private var renewalLabel: String {
        if case .trial = paymentGateway.subscriptionStatus {
            return "Trial ends:"
        }
        if case .subscribed(_, _, let willRenew) = paymentGateway.subscriptionStatus {
            return willRenew ? "Renews:" : "Expires:"
        }
        return "Expires:"
    }

    private func restore() {
        isRestoring = true
        restoreMessage = nil
        Task {
            do {
                try await paymentGateway.restorePurchases()
                if paymentGateway.subscriptionStatus.hasPremiumAccess {
                    restoreMessage = "Subscription restored."
                } else {
                    restoreMessage = "No active subscription found."
                }
            } catch {
                restoreMessage = error.localizedDescription
            }
            isRestoring = false
        }
    }
}
