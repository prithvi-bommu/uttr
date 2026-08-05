import SwiftUI

@main
struct UttrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var env = AppEnvironment.shared
    @State private var showOnboarding = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: env.appState, configStore: env.configStore)
                .onAppear {
                    if !env.configStore.settings.hasCompletedOnboarding && !showOnboarding {
                        showOnboarding = true
                    }
                }
        } label: {
            Image(systemName: env.appState.dictationState.menuBarIcon)
                .accessibilityLabel("Uttr")
        }

        Settings {
            SettingsView(store: env.configStore, permissionService: env.permissionService)
        }

        Window("Welcome to Uttr", id: "onboarding") {
            OnboardingView(permissionService: env.permissionService) {
                try? env.configStore.update { $0.hasCompletedOnboarding = true }
                showOnboarding = false
                NSApplication.shared.keyWindow?.close()
            }
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
    }
}
