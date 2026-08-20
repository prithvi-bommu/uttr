import SwiftUI

/// Settings for AI Content mode: a second hold-to-talk hotkey (⌥A) whose
/// transcript is sent to a configurable AI backend, with the response pasted.
struct AIContentSettingsView: View {
    @Bindable var store: ConfigurationStore
    var paymentGateway: (any PaymentGateway)?
    /// Re-registers the AI hotkey when the enabled state changes.
    var onConfigChanged: (() -> Void)?
    @State private var revealKey = false
    @State private var showPaywall = false

    var body: some View {
        Form {
            Section("AI Content") {
                if paymentGateway?.subscriptionStatus.hasPremiumAccess != true {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Uttr Pro Feature", systemImage: "lock.fill")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(
                            "Hold ⌥A and speak a request (\u{201C}write an email to…\u{201D}). "
                            + "The AI\u{2019}s response is pasted instead of your words. "
                            + "Upgrade to Uttr Pro to enable this feature."
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // Offered only when there is a gateway to buy through;
                        // the paywall sheet has nothing to present without one.
                        if paymentGateway != nil {
                            Button("Upgrade to Uttr Pro") {
                                showPaywall = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Toggle("Enable AI content mode", isOn: Binding(
                        get: { store.settings.aiContent.enabled },
                        set: { newValue in
                            try? store.update { $0.aiContent.enabled = newValue }
                            onConfigChanged?()
                        }
                    ))
                    Text(
                        "Hold ⌥A and speak a request (\u{201C}write an email to…\u{201D}). "
                        + "The transcription happens on-device; only the transcribed text "
                        + "is sent to the provider below, and the AI\u{2019}s response is pasted "
                        + "instead of your words. Audio never leaves your Mac."
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if store.settings.aiContent.enabled, paymentGateway?.subscriptionStatus.hasPremiumAccess == true {
                Section("Provider") {
                    Picker("Backend:", selection: Binding(
                        get: { store.settings.aiContent.provider },
                        set: { newValue in
                            try? store.update { $0.aiContent.provider = newValue }
                        }
                    )) {
                        Text("HTTP endpoint (OpenAI-compatible)").tag(AIProviderKind.httpEndpoint)
                        Text("Anthropic").tag(AIProviderKind.anthropic)
                        Text("Command-line tool").tag(AIProviderKind.commandLine)
                    }
                    .pickerStyle(.radioGroup)
                }

                switch store.settings.aiContent.provider {
                case .httpEndpoint: httpSection
                case .anthropic: anthropicSection
                case .commandLine: cliSection
                }

                Section("Request") {
                    HStack {
                        Text("Timeout:")
                        TextField("", value: Binding(
                            get: { store.settings.aiContent.timeoutSeconds },
                            set: { newValue in
                                try? store.update { $0.aiContent.timeoutSeconds = max(5, min(120, newValue)) }
                            }
                        ), format: .number)
                        .frame(width: 60)
                        Text("seconds (5–120)").foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("System prompt:")
                        TextEditor(text: Binding(
                            get: { store.settings.aiContent.systemPrompt },
                            set: { newValue in
                                try? store.update { $0.aiContent.systemPrompt = newValue }
                            }
                        ))
                        .font(.caption.monospaced())
                        .frame(height: 70)
                        Button("Reset to default") {
                            try? store.update { $0.aiContent.systemPrompt = AIContentConfig.defaultSystemPrompt }
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showPaywall) {
            if let paymentGateway {
                UttrPaywallView(
                    paymentGateway: paymentGateway,
                    onDismiss: { showPaywall = false }
                )
            }
        }
    }

    private var httpSection: some View {
        Section("HTTP Endpoint") {
            HStack {
                Text("Base URL:")
                TextField("https://api.openai.com/v1", text: Binding(
                    get: { store.settings.aiContent.http.baseURL },
                    set: { v in try? store.update { $0.aiContent.http.baseURL = v } }
                ))
                .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Model:")
                TextField("Model", text: Binding(
                    get: { store.settings.aiContent.http.model },
                    set: { v in try? store.update { $0.aiContent.http.model = v } }
                ))
                .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("API Key:")
                if revealKey {
                    TextField("API Key (optional for local servers)", text: httpKeyBinding)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("API Key (optional for local servers)", text: httpKeyBinding)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("Show", isOn: $revealKey).toggleStyle(.checkbox)
            }
            Text(
                "Works with any OpenAI-compatible chat-completions server: "
                + "api.openai.com, a local model server, or a gateway you have "
                + "access to. Configure the URL for your environment — no key "
                + "needed for most local servers."
            )
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var httpKeyBinding: Binding<String> {
        Binding(
            get: { store.settings.aiContent.http.apiKey },
            set: { v in try? store.update { $0.aiContent.http.apiKey = v } }
        )
    }

    private var anthropicSection: some View {
        Section("Anthropic") {
            HStack {
                Text("Model:")
                TextField("Model", text: Binding(
                    get: { store.settings.aiContent.anthropic.model },
                    set: { v in try? store.update { $0.aiContent.anthropic.model = v } }
                ))
                .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("API Key:")
                if revealKey {
                    TextField("API Key", text: anthropicKeyBinding)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("API Key", text: anthropicKeyBinding)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("Show", isOn: $revealKey).toggleStyle(.checkbox)
            }
        }
    }

    private var anthropicKeyBinding: Binding<String> {
        Binding(
            get: { store.settings.aiContent.anthropic.apiKey },
            set: { v in try? store.update { $0.aiContent.anthropic.apiKey = v } }
        )
    }

    private var cliSection: some View {
        Section("Command-Line Tool") {
            HStack {
                Text("Executable:")
                TextField("/path/to/tool", text: Binding(
                    get: { store.settings.aiContent.cli.executablePath },
                    set: { v in try? store.update { $0.aiContent.cli.executablePath = v } }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            }
            HStack {
                Text("Arguments:")
                TextField("space-separated; {prompt} substitutes the prompt", text: Binding(
                    get: { store.settings.aiContent.cli.arguments.joined(separator: " ") },
                    set: { v in
                        try? store.update {
                            $0.aiContent.cli.arguments = v.split(separator: " ").map(String.init)
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            }
            Text(
                "Runs a local tool of your choice: the prompt is piped to stdin "
                + "(or substituted for {prompt} in the arguments) and the tool\u{2019}s "
                + "output is pasted. Configuration stays on this Mac."
            )
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
