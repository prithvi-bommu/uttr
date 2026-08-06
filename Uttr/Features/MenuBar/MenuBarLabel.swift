import SwiftUI

/// Status-bar label for the MenuBarExtra. Rendered at app launch (unlike the
/// menu content, which appears only on click), so it doubles as the reliable
/// first-run hook that opens the onboarding window when
/// `hasCompletedOnboarding` is false.
struct MenuBarLabel: View {
    let appState: AppState
    let configStore: ConfigurationStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: appState.dictationState.menuBarIcon)
            .accessibilityLabel("Uttr")
            .onAppear {
                guard !configStore.settings.hasCompletedOnboarding else { return }
                // Defer one runloop turn so the window scene is registered
                // before we ask it to open.
                DispatchQueue.main.async {
                    openWindow(id: "onboarding")
                    NSApplication.shared.activate()
                }
            }
    }
}
