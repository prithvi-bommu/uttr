import Foundation

struct UttrSettings: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    var hasCompletedOnboarding: Bool = false
    var hotkey: HotkeyConfig = HotkeyConfig()
    var transcriptionEngine: TranscriptionEngineSelection = .automatic
    var whisperModel: String = "small.en"
    var cloudPolish: CloudPolishConfig = CloudPolishConfig()
    var localPolish: LocalPolishConfig = LocalPolishConfig()
    var aiContent: AIContentConfig = AIContentConfig()
    var startAtLogin: Bool = false

    static let `default` = UttrSettings()

    static let validWhisperModels = ["tiny.en", "base.en", "small.en", "medium.en"]

    enum ValidationError: LocalizedError, Equatable {
        case unsupportedSchemaVersion(Int)
        case hotkeyMissingModifier
        case hotkeyMissingKey
        case polishEnabledWithoutKey
        case polishEnabledWithoutModel
        case timeoutOutOfRange

        var errorDescription: String? {
            switch self {
            case .unsupportedSchemaVersion(let v):
                "Unsupported schema version \(v)."
            case .hotkeyMissingModifier:
                "Shortcut must include at least one modifier key."
            case .hotkeyMissingKey:
                "Shortcut must include a non-modifier key."
            case .polishEnabledWithoutKey:
                "An API key is required when text polish is enabled."
            case .polishEnabledWithoutModel:
                "A model is required when text polish is enabled."
            case .timeoutOutOfRange:
                "Timeout must be between 3 and 20 seconds."
            }
        }
    }

    func validate() throws {
        if schemaVersion != 1 {
            throw ValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        // Bare Fn/Globe is a valid hold-to-talk hotkey with no modifiers
        // (ADR-008). Every other key still requires at least one modifier.
        let isBareFnHotkey = hotkey.keyCode == Hotkey.fnGlobeKeyCode && hotkey.modifiers.isEmpty
        if !isBareFnHotkey {
            if hotkey.modifiers.isEmpty {
                throw ValidationError.hotkeyMissingModifier
            }
            if hotkey.keyCode == 0 {
                throw ValidationError.hotkeyMissingKey
            }
        }
        if cloudPolish.enabled && cloudPolish.provider != .none {
            let config = activeProviderConfig
            if let config {
                if config.apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                    throw ValidationError.polishEnabledWithoutKey
                }
                if config.model.trimmingCharacters(in: .whitespaces).isEmpty {
                    throw ValidationError.polishEnabledWithoutModel
                }
            }
        }
        if cloudPolish.timeoutSeconds < 3 || cloudPolish.timeoutSeconds > 20 {
            throw ValidationError.timeoutOutOfRange
        }
    }

    var activeProviderConfig: ProviderConfig? {
        switch cloudPolish.provider {
        case .none: nil
        case .openAI: cloudPolish.openAI
        case .anthropic: cloudPolish.anthropic
        }
    }

    mutating func sanitize() {
        if !Self.validWhisperModels.contains(whisperModel) {
            whisperModel = "small.en"
        }
        cloudPolish.timeoutSeconds = max(3, min(20, cloudPolish.timeoutSeconds))
    }
}

struct HotkeyConfig: Codable, Equatable, Sendable {
    var keyCode: UInt16 = 49
    var modifiers: [ModifierKey] = [.control, .option]
}

enum ModifierKey: String, Codable, Equatable, Sendable {
    case control
    case option
    case command
    case shift
}

enum TranscriptionEngineSelection: String, Codable, Equatable, Sendable {
    case automatic
    case systemSpeech
    case whisperKit
}

struct CloudPolishConfig: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var provider: PolishProvider = .none
    var openAI: ProviderConfig = ProviderConfig(apiKey: "", model: "gpt-5.6-luna")
    var anthropic: ProviderConfig = ProviderConfig(apiKey: "", model: "claude-haiku-4-5")
    var timeoutSeconds: Int = 8
}

enum PolishProvider: String, Codable, Equatable, Sendable {
    case none
    case openAI
    case anthropic
}

struct ProviderConfig: Codable, Equatable, Sendable {
    var apiKey: String
    var model: String
}

/// Offline, rule-based transcript cleanup (no network, no API key).
/// Applied after transcription when `enabled` is true.
struct LocalPolishConfig: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var removeFillers: Bool = true
    var collapseDuplicates: Bool = true
    var capitalizeSentences: Bool = true
}

/// "AI Content" mode: a second hold-to-talk hotkey whose transcript is sent
/// to a configurable AI backend as a prompt; the response is pasted instead
/// of the raw dictation. Off by default.
///
/// Providers are deliberately generic so that backend choice is pure runtime
/// configuration (this file lives in Application Support, never in the repo):
/// - `httpEndpoint`: any OpenAI-compatible chat-completions server — real
///   OpenAI, a local Ollama, LiteLLM, or any compatible gateway (base URL
///   is configurable).
/// - `anthropic`: the Anthropic messages API.
/// - `commandLine`: run a local executable with the prompt and paste its
///   stdout — lets any locally-installed CLI act as the backend.
struct AIContentConfig: Codable, Equatable, Sendable {
    var enabled: Bool = false
    /// Default ⌥A (keyCode 0 = "a").
    var hotkey: HotkeyConfig = HotkeyConfig(keyCode: 0, modifiers: [.option])
    var provider: AIProviderKind = .httpEndpoint
    var http: HTTPProviderConfig = HTTPProviderConfig()
    var anthropic: ProviderConfig = ProviderConfig(apiKey: "", model: "claude-haiku-4-5")
    var cli: CLIProviderConfig = CLIProviderConfig()
    var timeoutSeconds: Int = 30
    /// Prepended to every request so responses paste cleanly.
    var systemPrompt: String = AIContentConfig.defaultSystemPrompt

    static let defaultSystemPrompt = """
    You produce content requested by voice. Respond with ONLY the requested \
    content itself - no preamble, no explanations, no markdown fences, no \
    closing remarks. If the request is ambiguous, make reasonable assumptions.
    """
}

enum AIProviderKind: String, Codable, Equatable, Sendable, CaseIterable {
    case httpEndpoint
    case anthropic
    case commandLine
}

/// OpenAI-compatible chat-completions endpoint. Base URL is configurable so
/// the same code serves api.openai.com, a local server, or any gateway.
struct HTTPProviderConfig: Codable, Equatable, Sendable {
    var baseURL: String = "https://api.openai.com/v1"
    var apiKey: String = ""
    var model: String = "gpt-5.6-luna"
}

/// Local executable backend. The prompt is passed on stdin; stdout is the
/// response. `arguments` supports an optional "{prompt}" placeholder for
/// tools that take the prompt as an argument instead.
struct CLIProviderConfig: Codable, Equatable, Sendable {
    var executablePath: String = ""
    var arguments: [String] = []
}


// MARK: - Backward-compatible decoding

extension UttrSettings {
    /// Tolerant decoder: every field falls back to its default when the key is
    /// absent. Without this, adding any new field (e.g. `localPolish`) would
    /// make the synthesized decoder throw `keyNotFound` on configs written by
    /// older builds, and `ConfigurationStore.load()` would silently reset the
    /// user's whole configuration to defaults. Encoding stays synthesized.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        self.hotkey = try container.decodeIfPresent(HotkeyConfig.self, forKey: .hotkey) ?? HotkeyConfig()
        self.transcriptionEngine = try container.decodeIfPresent(TranscriptionEngineSelection.self, forKey: .transcriptionEngine) ?? .automatic
        self.whisperModel = try container.decodeIfPresent(String.self, forKey: .whisperModel) ?? "small.en"
        self.cloudPolish = try container.decodeIfPresent(CloudPolishConfig.self, forKey: .cloudPolish) ?? CloudPolishConfig()
        self.localPolish = try container.decodeIfPresent(LocalPolishConfig.self, forKey: .localPolish) ?? LocalPolishConfig()
        self.aiContent = try container.decodeIfPresent(AIContentConfig.self, forKey: .aiContent) ?? AIContentConfig()
        self.startAtLogin = try container.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? false
    }
}
