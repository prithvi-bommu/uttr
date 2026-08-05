import SwiftUI

struct MenuBarView: View {
    let appState: AppState
    let configStore: ConfigurationStore

    var body: some View {
        Text(statusText)
            .disabled(true)

        Text(hotkeyLabel)
            .disabled(true)

        Divider()

        SettingsLink {
            Text("Settings…")
        }

        Button("Check permissions…") {
        }

        Button("View privacy details…") {
        }

        Divider()

        Button("Quit Uttr") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusText: String {
        if let failedText = appState.pasteFailedText, !failedText.isEmpty {
            return "Paste failed — text copied"
        }
        return appState.dictationState.statusText
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
