import SwiftUI

struct PolishSettingsView: View {
    @Bindable var store: ConfigurationStore
    var paymentGateway: (any PaymentGateway)?
    var keyTester = PolishKeyTester()
    @State private var revealOpenAIKey = false
    @State private var revealAnthropicKey = false
    @State private var testKeyResult: String?
    @State private var testingKey = false
    @State private var showPaywall = false

    var body: some View {
        Form {
            Section("Local Cleanup (offline)") {
                Toggle("Clean up transcript on device", isOn: Binding(
                    get: { store.settings.localPolish.enabled },
                    set: { newValue in
                        try? store.update { $0.localPolish.enabled = newValue }
                    }
                ))
                Text("Runs a fast rule-based pass entirely on your Mac — no network, no API key. Applied after transcription and before pasting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if store.settings.localPolish.enabled {
                    Toggle("Remove filler words (um, uh, …)", isOn: Binding(
                        get: { store.settings.localPolish.removeFillers },
                        set: { newValue in
                            try? store.update { $0.localPolish.removeFillers = newValue }
                        }
                    ))
                    Toggle("Collapse repeated words", isOn: Binding(
                        get: { store.settings.localPolish.collapseDuplicates },
                        set: { newValue in
                            try? store.update { $0.localPolish.collapseDuplicates = newValue }
                        }
                    ))
                    Toggle("Capitalize sentences", isOn: Binding(
                        get: { store.settings.localPolish.capitalizeSentences },
                        set: { newValue in
                            try? store.update { $0.localPolish.capitalizeSentences = newValue }
                        }
                    ))
                }
            }

            Section("Cloud Text Polish") {
                if let gateway = paymentGateway, !gateway.subscriptionStatus.hasPremiumAccess {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Uttr Pro Feature", systemImage: "lock.fill")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Cloud Text Polish sends your transcript to an AI provider for natural-sounding cleanup. Upgrade to Uttr Pro to enable this feature.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Upgrade to Uttr Pro") {
                            showPaywall = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                } else {
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
            }

            if store.settings.cloudPolish.enabled, paymentGateway?.subscriptionStatus.hasPremiumAccess != false {
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

                Section("Timing") {
                    HStack {
                        Text("Polish budget:")
                        TextField("", value: Binding(
                            get: { store.settings.cloudPolish.polishBudgetMs },
                            set: { newValue in
                                try? store.update { $0.cloudPolish.polishBudgetMs = newValue }
                            }
                        ), format: .number)
                        .frame(width: 60)
                        Text("ms (50–2000)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Transport timeout:")
                        TextField("", value: Binding(
                            get: { store.settings.cloudPolish.timeoutSeconds },
                            set: { newValue in
                                try? store.update { $0.cloudPolish.timeoutSeconds = newValue }
                            }
                        ), format: .number)
                        .frame(width: 60)
                        Text("seconds (1–20)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showPaywall) {
            UttrPaywallView(
                onDismiss: { showPaywall = false },
                onPurchaseCompleted: {
                    showPaywall = false
                    try? store.update { $0.cloudPolish.enabled = true }
                }
            )
        }
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

            HStack {
                Button(testingKey ? "Testing…" : "Test Key…") {
                    let provider = store.settings.cloudPolish.provider
                    let config = ProviderConfig(
                        apiKey: apiKey.wrappedValue,
                        model: model.wrappedValue
                    )
                    let timeout = store.settings.cloudPolish.timeoutSeconds
                    testingKey = true
                    testKeyResult = nil
                    Task {
                        let result = await keyTester.test(
                            provider: provider, config: config,
                            timeoutSeconds: timeout)
                        testKeyResult = result.displayText
                        testingKey = false
                    }
                }
                .disabled(testingKey || apiKey.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
                if testingKey {
                    ProgressView()
                        .controlSize(.small)
                }
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
