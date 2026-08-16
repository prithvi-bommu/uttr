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

            Section("Clipboard") {
                Text("After pasting, Uttr restores your previous plain-text clipboard content only if no other app has changed the clipboard in the meantime. If the clipboard held non-text data (images, files), Uttr does not attempt restoration. If pasting fails, the transcribed text stays on your clipboard so you can paste it manually with Command-V.")
            }

            Section("No Tracking") {
                Text("Uttr does not collect analytics, telemetry, usage statistics, crash reports, or any personal information. There are no accounts or cloud sync features.")
            }

            Section("Subscriptions") {
                Text("Uttr Pro subscriptions are managed through RevenueCat, which communicates with the App Store on your behalf. RevenueCat receives only the transaction data Apple provides (product ID, purchase date, expiry). No audio, transcripts, clipboard contents, or personal information are shared with RevenueCat. Your subscription status is cached locally so premium features work offline.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
