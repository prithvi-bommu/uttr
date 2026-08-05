import Foundation

struct UttrSettings: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    var hasCompletedOnboarding: Bool = false
    var hotkey: HotkeyConfig = HotkeyConfig()
    var transcriptionEngine: TranscriptionEngineSelection = .automatic
    var whisperModel: String = "small.en"
    var cloudPolish: CloudPolishConfig = CloudPolishConfig()
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
        if hotkey.modifiers.isEmpty {
            throw ValidationError.hotkeyMissingModifier
        }
        if hotkey.keyCode == 0 {
            throw ValidationError.hotkeyMissingKey
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
