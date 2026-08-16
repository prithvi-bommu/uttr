import SwiftUI
import RevenueCatUI

struct UttrPaywallView: View {
    var onDismiss: (() -> Void)?
    var onPurchaseCompleted: (() -> Void)?

    var body: some View {
        PaywallView()
            .onPurchaseCompleted { _ in
                onPurchaseCompleted?()
            }
            .onRestoreCompleted { _ in
                onPurchaseCompleted?()
            }
        .frame(minWidth: 400, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    onDismiss?()
                }
            }
        }
    }
}
