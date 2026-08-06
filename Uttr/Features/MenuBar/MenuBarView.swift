import SwiftUI

struct MenuBarView: View {
    let appState: AppState
    let configStore: ConfigurationStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusText)
            .disabled(true)

        Text(hotkeyLabel)
            .disabled(!appState.dictationState.isIdle)

        Divider()

        SettingsLink {
            Text("Settings…")
        }

        Button("Check permissions…") {
            SettingsLink.showSettings()
        }

        Button("View privacy details…") {
            SettingsLink.showSettings()
        }

        #if DEBUG
        Button("Diagnostics…") {
            openWindow(id: "diagnostics")
            NSApplication.shared.activate()
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

    private var hotkeyLabel: String {
        let hotkey = configStore.settings.hotkey
        let h = Hotkey(
            keyCode: hotkey.keyCode,
            modifiers: Set(hotkey.modifiers)
        )
        return "Dictate with \(h.displayString)"
    }
}

private extension SettingsLink where Label == Text {
    @MainActor
    static func showSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApplication.shared.activate()
    }
}
