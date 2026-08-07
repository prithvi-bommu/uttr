import Combine
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var store: ConfigurationStore
    let appState: AppState
    let onBeginCapture: () -> Void
    let onCancelCapture: () -> Void
    /// Applies the login-item change to the system; returns false on refusal.
    /// Nil (previews/tests) falls back to persisting the setting only.
    var onStartAtLoginChanged: ((Bool) -> Bool)? = nil
    var fnUsage: FnUsageChecking = RealFnUsageService()

    @State private var fnGlobeAction: FnGlobeAction = .unknown
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Start Uttr at login", isOn: Binding(
                    get: { store.settings.startAtLogin },
                    set: { newValue in
                        if let onStartAtLoginChanged {
                            if onStartAtLoginChanged(newValue) {
                                loginItemError = nil
                            } else {
                                loginItemError = "macOS refused the change. Check System Settings → General → Login Items."
                            }
                        } else {
                            try? store.update { $0.startAtLogin = newValue }
                        }
                    }
                ))
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Dictation Shortcut") {
                if appState.dictationState == .awaitingHotkey {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Press and hold your shortcut, then release.")
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)

                        Button("Cancel") {
                            onCancelCapture()
                        }
                    }
                } else {
                    HStack {
                        Text("Current shortcut:")
                        Text(currentHotkeyDisplay)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Spacer()

                        Button("Change Shortcut…") {
                            onBeginCapture()
                        }
                        .disabled(!appState.canChangeSettings)
                    }
                }

                if showFnConflictWarning {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Your 🌐 key is currently set to “\(fnGlobeAction.displayName)”, so macOS will also trigger that on every press. For hold-to-talk with the 🌐/Fn key, set “Press 🌐 key to” to “Do Nothing” in Keyboard settings.")
                                .font(.caption)
                            Button("Open Keyboard Settings") {
                                fnUsage.openKeyboardSettings()
                            }
                        }
                    }
                    .padding(8)
                    .background(.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Text("You can also use the 🌐/Fn key alone: first set System Settings → Keyboard → “Press 🌐 key to” to “Do Nothing”, then click Change Shortcut and press and release the 🌐/Fn key. Fn cannot be combined with other keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            refreshFnAction()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            // Re-check after the user returns from System Settings.
            refreshFnAction()
        }
    }

    /// Warn when the active hotkey is bare Fn but the system will also fire
    /// its own Globe action on every press (ADR-008).
    private var showFnConflictWarning: Bool {
        let hotkey = store.settings.hotkey
        let isFnHotkey = hotkey.keyCode == Hotkey.fnGlobeKeyCode && hotkey.modifiers.isEmpty
        return isFnHotkey && fnGlobeAction != .doNothing
    }

    private func refreshFnAction() {
        fnGlobeAction = fnUsage.currentAction()
    }

    private var currentHotkeyDisplay: String {
        let hotkey = store.settings.hotkey
        let h = Hotkey(
            keyCode: hotkey.keyCode,
            modifiers: Set(hotkey.modifiers)
        )
        return h.displayString
    }
}
