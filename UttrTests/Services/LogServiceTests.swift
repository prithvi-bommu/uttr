import Testing
@testable import Uttr

@Suite("LogService")
struct LogServiceTests {
    @Test("all loggers are accessible")
    func loggersAccessible() {
        _ = LogService.general
        _ = LogService.audio
        _ = LogService.transcription
        _ = LogService.hotkey
        _ = LogService.paste
        _ = LogService.polish
        _ = LogService.config
        _ = LogService.permissions
    }
}
