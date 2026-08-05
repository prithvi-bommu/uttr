import SwiftUI

@main
struct UttrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var env = AppEnvironment.shared
    @State private var permissionAlert: PermissionAlertInfo?

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: env.appState, configStore: env.configStore)
                .onAppear {
                    if !env.configStore.settings.hasCompletedOnboarding {
                    }
                }
        } label: {
            Image(systemName: env.appState.dictationState.menuBarIcon)
                .accessibilityLabel("Uttr")
        }

        Settings {
            SettingsView(
                store: env.configStore,
                appState: env.appState,
                permissionService: env.permissionService,
                onBeginCapture: { env.beginShortcutCapture() },
                onCancelCapture: { env.cancelShortcutCapture() }
            )
        }

        Window("Welcome to Uttr", id: "onboarding") {
            OnboardingView(permissionService: env.permissionService) {
                try? env.configStore.update { $0.hasCompletedOnboarding = true }
                NSApplication.shared.keyWindow?.close()
            }
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
    }
}
