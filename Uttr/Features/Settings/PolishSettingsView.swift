import SwiftUI

struct PolishSettingsView: View {
    @Bindable var store: ConfigurationStore
    @State private var revealOpenAIKey = false
    @State private var revealAnthropicKey = false
    @State private var testKeyResult: String?

    var body: some View {
        Form {
            Section("Text Polish") {
                Toggle("Enable text polish", isOn: Binding(
                    get: { store.settings.cloudPolish.enabled },
                    set: { newValue in
                        try? store.update { $0.cloudPolish.enabled = newValue }
                    }
                ))
                Text("When enabled, Uttr sends only the final transcript text to the selected provider for cleanup. Audio is never sent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.settings.cloudPolish.enabled {
                Section("Provider") {
                    Picker("Provider:", selection: Binding(
                        get: { store.settings.cloudPolish.provider },
                        set: { newValue in
                            try? store.update { $0.cloudPolish.provider = newValue }
                        }
                    )) {
                        Text("None").tag(PolishProvider.none)
                        Text("OpenAI").tag(PolishProvider.openAI)
                        Text("Anthropic").tag(PolishProvider.anthropic)
                    }
                    .pickerStyle(.radioGroup)
                }

                if store.settings.cloudPolish.provider == .openAI {
                    providerSection(
                        title: "OpenAI",
                        apiKey: Binding(
                            get: { store.settings.cloudPolish.openAI.apiKey },
                            set: { newValue in
                                try? store.update { $0.cloudPolish.openAI.apiKey = newValue }
                            }
                        ),
                        model: Binding(
                            get: { store.settings.cloudPolish.openAI.model },
                            set: { newValue in
                                try? store.update { $0.cloudPolish.openAI.model = newValue }
                            }
                        ),
                        defaultModel: "gpt-5.6-luna",
                        revealKey: $revealOpenAIKey
                    )
                }

                if store.settings.cloudPolish.provider == .anthropic {
                    providerSection(
                        title: "Anthropic",
                        apiKey: Binding(
                            get: { store.settings.cloudPolish.anthropic.apiKey },
                            set: { newValue in
                                try? store.update { $0.cloudPolish.anthropic.apiKey = newValue }
                            }
                        ),
                        model: Binding(
                            get: { store.settings.cloudPolish.anthropic.model },
                            set: { newValue in
                                try? store.update { $0.cloudPolish.anthropic.model = newValue }
                            }
                        ),
                        defaultModel: "claude-haiku-4-5",
                        revealKey: $revealAnthropicKey
                    )
                }

                Section("Timeout") {
                    HStack {
                        Text("Timeout:")
                        TextField("", value: Binding(
                            get: { store.settings.cloudPolish.timeoutSeconds },
                            set: { newValue in
                                try? store.update { $0.cloudPolish.timeoutSeconds = newValue }
                            }
                        ), format: .number)
                        .frame(width: 60)
                        Text("seconds (3–20)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func providerSection(
        title: String,
        apiKey: Binding<String>,
        model: Binding<String>,
        defaultModel: String,
        revealKey: Binding<Bool>
    ) -> some View {
        Section(title) {
            HStack {
                Text("Model:")
                TextField("Model", text: model)
                    .textFieldStyle(.roundedBorder)
                Button("Reset") {
                    model.wrappedValue = defaultModel
                }
            }

            HStack {
                Text("API Key:")
                if revealKey.wrappedValue {
                    TextField("API Key", text: apiKey)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("API Key", text: apiKey)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("Show", isOn: revealKey)
                    .toggleStyle(.checkbox)
            }

            Button("Test Key…") {
            }

            if let result = testKeyResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Your API key is saved in Uttr's local configuration file as plaintext. It is not sent anywhere except to the provider you select when text polishing is enabled. Use a provider spending limit and do not use a high-privilege key.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .accessibilityIdentifier("plaintextDisclosure")
        }
    }
}
