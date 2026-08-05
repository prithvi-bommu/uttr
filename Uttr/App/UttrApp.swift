import SwiftUI

@main
struct UttrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(systemName: "mic.circle")
                .accessibilityLabel("Uttr")
        }

        Settings {
            Text("Settings placeholder")
                .frame(width: 400, height: 300)
        }
    }
}
