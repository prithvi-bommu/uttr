import SwiftUI

struct MenuBarView: View {
    var body: some View {
        Text("Ready")
            .disabled(true)

        Text("Dictate with Control-Option-Space")
            .disabled(true)

        Divider()

        SettingsLink {
            Text("Settings...")
        }

        Button("Check permissions...") {
        }

        Button("View privacy details...") {
        }

        Divider()

        Button("Quit Uttr") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
