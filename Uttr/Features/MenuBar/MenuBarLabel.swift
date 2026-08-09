import SwiftUI

/// Status-bar label for the MenuBarExtra. Rendered at app launch (unlike the
/// menu content, which appears only on click), so it doubles as the reliable
/// launch hook that opens the setup window when the user needs it:
/// - true first run (`hasCompletedOnboarding == false`), or
/// - any required permission missing (spec §9: at launch, if a permission is
///   absent, show guidance) — the normal state right after installing from a
///   DMG on a machine whose config predates the install.
struct MenuBarLabel: View {
    let appState: AppState
    let configStore: ConfigurationStore
    var permissionService: PermissionChecking?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: appState.dictationState.menuBarIcon)
            .accessibilityLabel("Uttr")
            .onAppear {
                guard needsSetup else { return }
                // Defer one runloop turn so the window scene is registered
                // before we ask it to open.
                DispatchQueue.main.async {
                    openWindow(id: "onboarding")
                    // Cooperative activation ignores plain activate() from
                    // accessory apps — the setup window opened buried under
                    // other apps' windows. Force it to the front.
                    WindowFocus.focusWindow(sceneID: "onboarding")
                }
            }
    }

    private var needsSetup: Bool {
        if !configStore.settings.hasCompletedOnboarding { return true }
        guard let permissionService else { return false }
        // .unknown (mic notDetermined) counts as missing: the user has never
        // been prompted, so dictation cannot work yet.
        return permissionService.microphoneStatus() != .granted
            || permissionService.inputMonitoringStatus() != .granted
            || permissionService.accessibilityStatus() != .granted
    }
}
