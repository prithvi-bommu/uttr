import Foundation
@testable import Uttr

final class MockHotkeyService: HotkeyServiceProtocol, @unchecked Sendable {
    var startCalled = false
    var stopCalled = false
    var lastHotkey: Hotkey?
    var isCapturing = false
    var captureCancelled = false
    private var callback: (@Sendable (HotkeyEvent) -> Void)?

    func start(hotkey: Hotkey, callback: @escaping @Sendable (HotkeyEvent) -> Void) {
        startCalled = true
        lastHotkey = hotkey
        self.callback = callback
    }

    func stop() {
        stopCalled = true
    }

    func updateHotkey(_ hotkey: Hotkey) {
        lastHotkey = hotkey
    }

    var lastAIHotkey: Hotkey?

    func updateAIHotkey(_ hotkey: Hotkey?) {
        lastAIHotkey = hotkey
    }

    func beginCapture() {
        isCapturing = true
        captureCancelled = false
    }

    func cancelCapture() {
        isCapturing = false
        captureCancelled = true
    }

    func simulateEvent(_ event: HotkeyEvent) {
        callback?(event)
    }
}
