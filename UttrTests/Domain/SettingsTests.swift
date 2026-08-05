import Testing
import Foundation
@testable import Uttr

@Suite("UttrSettings")
struct SettingsTests {
    @Test("default settings encode and decode")
    func defaultRoundTrip() throws {
        let settings = UttrSettings.default
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(UttrSettings.self, from: data)
        #expect(decoded == settings)
    }

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
}
