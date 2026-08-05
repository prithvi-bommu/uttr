import SwiftUI

struct TranscriptionSettingsView: View {
    @Bindable var store: ConfigurationStore

    var body: some View {
        Form {
            Section("Transcription Engine") {
                Picker("Engine:", selection: Binding(
                    get: { store.settings.transcriptionEngine },
                    set: { newValue in
                        try? store.update { $0.transcriptionEngine = newValue }
                    }
                )) {
                    Text("Automatic").tag(TranscriptionEngineSelection.automatic)
                    Text("System Speech (macOS 26+)").tag(TranscriptionEngineSelection.systemSpeech)
                    Text("WhisperKit").tag(TranscriptionEngineSelection.whisperKit)
                }
                .pickerStyle(.radioGroup)

                if store.settings.transcriptionEngine == .automatic {
                    Text("Uttr will use System Speech on macOS 26+ when available, otherwise WhisperKit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if store.settings.transcriptionEngine != .systemSpeech {
                Section("WhisperKit Model") {
                    Picker("Model:", selection: Binding(
                        get: { store.settings.whisperModel },
                        set: { newValue in
                            try? store.update { $0.whisperModel = newValue }
                        }
                    )) {
                        Text("Tiny (fastest, lowest accuracy)").tag("tiny.en")
                        Text("Base (fast)").tag("base.en")
                        Text("Small (default balance)").tag("small.en")
                        Text("Medium (slower, more accurate)").tag("medium.en")
                    }

                    HStack {
                        Button("Download Selected Model") {
                        }
                        Spacer()
                        Text("Not downloaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
