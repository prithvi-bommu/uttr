import Foundation

struct UttrSettings: Codable, Equatable {
    var schemaVersion: Int = 1
    var hasCompletedOnboarding: Bool = false
    var hotkey: HotkeyConfig = HotkeyConfig()
    var transcriptionEngine: TranscriptionEngineSelection = .automatic
    var whisperModel: String = "small.en"
    var cloudPolish: CloudPolishConfig = CloudPolishConfig()
    var startAtLogin: Bool = false

    static let `default` = UttrSettings()
}

struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt16 = 49
    var modifiers: [ModifierKey] = [.control, .option]
}

enum ModifierKey: String, Codable, Equatable {
    case control
    case option
    case command
    case shift
}

enum TranscriptionEngineSelection: String, Codable, Equatable {
    case automatic
    case systemSpeech
    case whisperKit
}

struct CloudPolishConfig: Codable, Equatable {
    var enabled: Bool = false
    var provider: PolishProvider = .none
    var openAI: ProviderConfig = ProviderConfig(apiKey: "", model: "gpt-5.6-luna")
    var anthropic: ProviderConfig = ProviderConfig(apiKey: "", model: "claude-haiku-4-5")
    var timeoutSeconds: Int = 8
}

enum PolishProvider: String, Codable, Equatable {
    case none
    case openAI
    case anthropic
}

struct ProviderConfig: Codable, Equatable {
    var apiKey: String
    var model: String
}
