import SwiftUI

struct PrivacySettingsView: View {
    var body: some View {
        Form {
            Section("Audio Privacy") {
                Text("Microphone audio stays entirely on your Mac. It is captured only while you hold your dictation shortcut, processed locally, and immediately discarded. Audio is never written to disk, transmitted over the network, or retained in any form.")
            }

            Section("Text Polish Privacy") {
                Text("When text polish is enabled and a provider is selected, only the final transcript text is sent to the chosen provider for cleanup. No audio, device identifiers, clipboard contents, file paths, or metadata are ever included in the request.")
            }

            Section("No Tracking") {
                Text("Uttr does not collect analytics, telemetry, usage statistics, crash reports, or any personal information. There are no accounts, subscriptions, or cloud sync features.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
