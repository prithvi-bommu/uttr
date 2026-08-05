import Testing
@testable import Uttr

@Suite("LogService")
struct LogServiceTests {
    @Test("all loggers use correct subsystem")
    func correctSubsystem() {
        #expect(LogService.general.subsystem == "com.uttr.app")
        #expect(LogService.audio.subsystem == "com.uttr.app")
        #expect(LogService.transcription.subsystem == "com.uttr.app")
        #expect(LogService.hotkey.subsystem == "com.uttr.app")
        #expect(LogService.paste.subsystem == "com.uttr.app")
        #expect(LogService.polish.subsystem == "com.uttr.app")
        #expect(LogService.config.subsystem == "com.uttr.app")
        #expect(LogService.permissions.subsystem == "com.uttr.app")
    }
}
