import SwiftUI

struct TranscriptionSettingsView: View {
    @Bindable var store: ConfigurationStore
    var coordinator: TranscriptionCoordinator?
    var onSelectionChanged: (() -> Void)?

    var body: some View {
        Form {
            Section("Transcription Engine") {
                Picker("Engine:", selection: Binding(
                    get: { store.settings.transcriptionEngine },
                    set: { newValue in
                        try? store.update { $0.transcriptionEngine = newValue }
                        onSelectionChanged?()
                    }
                )) {
                    Text("Automatic").tag(TranscriptionEngineSelection.automatic)
                    Text("System Speech (Experimental; macOS 26+)").tag(TranscriptionEngineSelection.systemSpeech)
                    Text("WhisperKit").tag(TranscriptionEngineSelection.whisperKit)
                }
                .pickerStyle(.radioGroup)

                if store.settings.transcriptionEngine == .automatic {
                    Text("Uttr uses WhisperKit. System Speech is available as an opt-in on macOS 26+.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if store.settings.transcriptionEngine == .systemSpeech {
                    Text("System Speech is unavailable on this macOS version. WhisperKit will be used until macOS 26+ support lands.")
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
                            onSelectionChanged?()
                        }
                    )) {
                        Text("Tiny (fastest, lowest accuracy)").tag("tiny.en")
                        Text("Base (fast)").tag("base.en")
                        Text("Small (default balance)").tag("small.en")
                        Text("Medium (slower, more accurate)").tag("medium.en")
                    }

                    HStack {
                        Button("Download Selected Model") {
                            onSelectionChanged?()
                        }
                        .disabled(coordinator?.preparationState == .preparing)
                        Spacer()
                        Text(coordinator?.preparationState.statusText ?? ModelPreparationState.notPrepared.statusText)
                            .font(.caption)
                            .foregroundStyle(statusColor)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var statusColor: Color {
        switch coordinator?.preparationState {
        case .ready: .green
        case .failed: .red
        default: .secondary
        }
    }
}
