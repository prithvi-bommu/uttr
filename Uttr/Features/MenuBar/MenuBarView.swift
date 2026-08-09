import SwiftUI

struct MenuBarView: View {
    let appState: AppState
    let configStore: ConfigurationStore
    var coordinator: TranscriptionCoordinator?
    var metrics: DictationMetrics?
    var permissionService: PermissionChecking?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusText)
            .disabled(true)

        if let engineLine {
            Text(engineLine)
                .disabled(true)
        }

        if let latencyLine {
            Text(latencyLine)
                .disabled(true)
        }

        Text(hotkeyLabel)
            .disabled(!appState.dictationState.isIdle)

        // Contextual one-click fix when a permission blocks dictation.
        if case .blocked(let blocker) = appState.dictationState, let permissionService {
            Button("Open \(blocker.settingsPaneName) settings…") {
                switch blocker {
                case .microphone: permissionService.openMicrophoneSettings()
                case .inputMonitoring: permissionService.openInputMonitoringSettings()
                case .accessibility: permissionService.openAccessibilitySettings()
                }
            }
        }

        Divider()

        Button("Settings…") {
            SettingsOpener.openAndFocus()
        }

        Button("Check permissions…") {
            SettingsOpener.openAndFocus()
        }

        Button("View privacy details…") {
            SettingsOpener.openAndFocus()
        }

        #if DEBUG
        Button("Diagnostics…") {
            openWindow(id: "diagnostics")
            WindowFocus.focusWindow(sceneID: "diagnostics")
        }
        #endif

        Divider()

        Button("Quit Uttr") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusText: String {
        if let failedText = appState.pasteFailedText, !failedText.isEmpty {
            return "Text copied — paste with Command-V."
        }
        return appState.dictationState.statusText
    }

    /// Engine readiness at a glance, so users don't need Settings to know
    /// whether the model is still downloading. Shown only when informative.
    private var engineLine: String? {
        guard let coordinator else { return nil }
        let engine = coordinator.activeEngineID == .systemSpeech ? "System Speech" : "WhisperKit \(configStore.settings.whisperModel)"
        switch coordinator.preparationState {
        case .ready:
            return nil // healthy steady state — don't add noise
        case .preparing:
            return "\(engine): downloading model…"
        case .failed:
            return "\(engine): model failed — see Settings"
        case .notPrepared:
            return "\(engine): model not downloaded"
        }
    }

    /// Redacted latency summary of the most recent successful dictation
    /// (duration and milliseconds only — never content, spec §11).
    private var latencyLine: String? {
        guard let record = metrics?.records.first(where: { $0.result == .completed }),
              let ms = record.releaseToPasteMs else { return nil }
        return String(format: "Last dictation: %.1fs → %d ms", record.audioDurationSeconds, ms)
    }

    private var hotkeyLabel: String {
        let hotkey = configStore.settings.hotkey
        let h = Hotkey(
            keyCode: hotkey.keyCode,
            modifiers: Set(hotkey.modifiers)
        )
        return "Dictate with \(h.displayString)"
    }
}

extension PermissionBlocker {
    var settingsPaneName: String {
        switch self {
        case .microphone: "Microphone"
        case .inputMonitoring: "Input Monitoring"
        case .accessibility: "Accessibility"
        }
    }
}

/// Opens the SwiftUI Settings scene and brings it to the front. The plain
/// `SettingsLink`/`showSettingsWindow:` path opens the window BEHIND other
/// apps because cooperative activation ignores accessory-app activation.
@MainActor
enum SettingsOpener {
    static func openAndFocus() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        WindowFocus.focusSettingsWindow()
    }
}
