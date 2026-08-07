import Foundation
import Testing
@testable import Uttr

@Suite("UttrSettings")
struct SettingsTests {

    // MARK: - Encoding

    @Test("default settings encode and decode")
    func defaultRoundTrip() throws {
        let settings = UttrSettings.default
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(UttrSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test("encoded JSON matches expected schema")
    func encodedSchema() throws {
        let data = try JSONEncoder().encode(UttrSettings.default)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["schemaVersion"] as? Int == 1)
        #expect(json["hasCompletedOnboarding"] as? Bool == false)
        #expect(json["transcriptionEngine"] as? String == "automatic")
        #expect(json["whisperModel"] as? String == "small.en")
        #expect(json["startAtLogin"] as? Bool == false)
    }

    // MARK: - Defaults

    @Test("default schema version is 1")
    func schemaVersion() {
        #expect(UttrSettings.default.schemaVersion == 1)
    }

    @Test("default hotkey is Control-Option-Space")
    func defaultHotkey() {
        let hotkey = UttrSettings.default.hotkey
        #expect(hotkey.keyCode == 49)
        #expect(hotkey.modifiers == [.control, .option])
    }

    @Test("cloud polish disabled by default")
    func cloudPolishDisabledByDefault() {
        #expect(UttrSettings.default.cloudPolish.enabled == false)
        #expect(UttrSettings.default.cloudPolish.provider == .none)
    }

    @Test("default transcription engine is automatic")
    func defaultEngine() {
        #expect(UttrSettings.default.transcriptionEngine == .automatic)
    }

    @Test("default whisper model is small.en")
    func defaultWhisperModel() {
        #expect(UttrSettings.default.whisperModel == "small.en")
    }

    @Test("onboarding not completed by default")
    func onboardingDefault() {
        #expect(UttrSettings.default.hasCompletedOnboarding == false)
    }

    @Test("start at login disabled by default")
    func startAtLoginDefault() {
        #expect(UttrSettings.default.startAtLogin == false)
    }

    @Test("default timeout is 8 seconds")
    func defaultTimeout() {
        #expect(UttrSettings.default.cloudPolish.timeoutSeconds == 8)
    }

    @Test("default OpenAI model")
    func defaultOpenAIModel() {
        #expect(UttrSettings.default.cloudPolish.openAI.model == "gpt-5.6-luna")
    }

    @Test("default Anthropic model")
    func defaultAnthropicModel() {
        #expect(UttrSettings.default.cloudPolish.anthropic.model == "claude-haiku-4-5")
    }

    // MARK: - Validation

    @Test("valid default settings pass validation")
    func validDefault() throws {
        try UttrSettings.default.validate()
    }

    @Test("unsupported schema version fails validation")
    func unsupportedSchema() {
        var settings = UttrSettings.default
        settings.schemaVersion = 2
        #expect(throws: UttrSettings.ValidationError.unsupportedSchemaVersion(2)) {
            try settings.validate()
        }
    }

    @Test("missing modifier fails validation")
    func missingModifier() {
        var settings = UttrSettings.default
        settings.hotkey.modifiers = []
        #expect(throws: UttrSettings.ValidationError.hotkeyMissingModifier) {
            try settings.validate()
        }
    }

    @Test("zero key code fails validation")
    func zeroKeyCode() {
        var settings = UttrSettings.default
        settings.hotkey.keyCode = 0
        #expect(throws: UttrSettings.ValidationError.hotkeyMissingKey) {
            try settings.validate()
        }
    }

    @Test("polish enabled with blank key fails")
    func polishWithBlankKey() {
        var settings = UttrSettings.default
        settings.cloudPolish.enabled = true
        settings.cloudPolish.provider = .anthropic
        settings.cloudPolish.anthropic.apiKey = "  "
        #expect(throws: UttrSettings.ValidationError.polishEnabledWithoutKey) {
            try settings.validate()
        }
    }

    @Test("polish enabled with blank model fails")
    func polishWithBlankModel() {
        var settings = UttrSettings.default
        settings.cloudPolish.enabled = true
        settings.cloudPolish.provider = .anthropic
        settings.cloudPolish.anthropic.apiKey = "sk-test"
        settings.cloudPolish.anthropic.model = ""
        #expect(throws: UttrSettings.ValidationError.polishEnabledWithoutModel) {
            try settings.validate()
        }
    }

    @Test("polish with none provider passes even with blank keys")
    func polishNoneProviderPasses() throws {
        var settings = UttrSettings.default
        settings.cloudPolish.enabled = true
        settings.cloudPolish.provider = .none
        try settings.validate()
    }

    @Test("timeout below 3 fails")
    func timeoutTooLow() {
        var settings = UttrSettings.default
        settings.cloudPolish.timeoutSeconds = 2
        #expect(throws: UttrSettings.ValidationError.timeoutOutOfRange) {
            try settings.validate()
        }
    }

    @Test("timeout above 20 fails")
    func timeoutTooHigh() {
        var settings = UttrSettings.default
        settings.cloudPolish.timeoutSeconds = 21
        #expect(throws: UttrSettings.ValidationError.timeoutOutOfRange) {
            try settings.validate()
        }
    }

    // MARK: - Sanitization

    @Test("unknown whisper model sanitized to small.en")
    func sanitizeUnknownModel() {
        var settings = UttrSettings.default
        settings.whisperModel = "unknown-model"
        settings.sanitize()
        #expect(settings.whisperModel == "small.en")
    }

    @Test("valid whisper models are preserved")
    func validModelsPreserved() {
        for model in UttrSettings.validWhisperModels {
            var settings = UttrSettings.default
            settings.whisperModel = model
            settings.sanitize()
            #expect(settings.whisperModel == model)
        }
    }

    @Test("timeout clamped to range")
    func timeoutClamped() {
        var settings = UttrSettings.default
        settings.cloudPolish.timeoutSeconds = 1
        settings.sanitize()
        #expect(settings.cloudPolish.timeoutSeconds == 3)

        settings.cloudPolish.timeoutSeconds = 50
        settings.sanitize()
        #expect(settings.cloudPolish.timeoutSeconds == 20)
    }

    // MARK: - Active provider config

    @Test("active provider config returns correct provider")
    func activeProviderConfig() {
        var settings = UttrSettings.default
        #expect(settings.activeProviderConfig == nil)

        settings.cloudPolish.provider = .openAI
        #expect(settings.activeProviderConfig == settings.cloudPolish.openAI)

        settings.cloudPolish.provider = .anthropic
        #expect(settings.activeProviderConfig == settings.cloudPolish.anthropic)
    }

    // MARK: - Local polish

    @Test("local polish defaults to disabled with all rules on")
    func localPolishDefaults() {
        let config = UttrSettings.default.localPolish
        #expect(config.enabled == false)
        #expect(config.removeFillers)
        #expect(config.collapseDuplicates)
        #expect(config.capitalizeSentences)
    }

    // MARK: - Backward-compatible decoding

    @Test("decodes config JSON missing the localPolish key without wiping other fields")
    func decodesLegacyConfig() throws {
        // Simulates a config written by a build before `localPolish` existed.
        let legacy = """
        {
          "schemaVersion": 1,
          "hasCompletedOnboarding": true,
          "whisperModel": "base.en",
          "transcriptionEngine": "whisperKit",
          "startAtLogin": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(UttrSettings.self, from: legacy)

        #expect(decoded.hasCompletedOnboarding == true)
        #expect(decoded.whisperModel == "base.en")
        #expect(decoded.transcriptionEngine == .whisperKit)
        #expect(decoded.startAtLogin == true)
        // Missing key falls back to default rather than throwing.
        #expect(decoded.localPolish == LocalPolishConfig())
    }

    @Test("empty JSON object decodes to defaults")
    func decodesEmptyObject() throws {
        let decoded = try JSONDecoder().decode(UttrSettings.self, from: "{}".data(using: .utf8)!)
        #expect(decoded == UttrSettings.default)
    }
}
