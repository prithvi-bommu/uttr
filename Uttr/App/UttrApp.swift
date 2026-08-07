import SwiftUI

@main
struct UttrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var env = AppEnvironment.shared
    @State private var permissionAlert: PermissionAlertInfo?

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                appState: env.appState,
                configStore: env.configStore,
                coordinator: env.transcriptionCoordinator,
                metrics: env.dictationMetrics,
                permissionService: env.permissionService
            )
        } label: {
            // The label renders in the status bar at launch, so this is the
            // reliable first-run hook (menu content only appears on click).
            MenuBarLabel(appState: env.appState, configStore: env.configStore, permissionService: env.permissionService)
        }

        Settings {
            SettingsView(
                store: env.configStore,
                appState: env.appState,
                permissionService: env.permissionService,
                onBeginCapture: { env.beginShortcutCapture() },
                onCancelCapture: { env.cancelShortcutCapture() },
                transcriptionCoordinator: env.transcriptionCoordinator,
                onTranscriptionChanged: { env.configureTranscription() },
                onStartAtLoginChanged: { env.applyStartAtLogin($0) },
                onAIConfigChanged: { env.applyAIHotkey() }
            )
        }

        #if DEBUG
        Window("Uttr Diagnostics", id: "diagnostics") {
            DiagnosticsView(metrics: env.dictationMetrics)
        }
        .windowResizability(.contentSize)
        #endif

        Window("Welcome to Uttr", id: "onboarding") {
            OnboardingView(
                permissionService: env.permissionService,
                hotkeyDisplay: Hotkey(
                    keyCode: env.configStore.settings.hotkey.keyCode,
                    modifiers: Set(env.configStore.settings.hotkey.modifiers)
                ).displayString
            ) {
                try? env.configStore.update { $0.hasCompletedOnboarding = true }
                NSApplication.shared.keyWindow?.close()
            }
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
    }
}
