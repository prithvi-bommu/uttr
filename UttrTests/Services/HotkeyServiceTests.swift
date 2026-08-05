import Foundation
import Testing
@testable import Uttr

private final class SendableCounter: @unchecked Sendable {
    private var _value = 0
    var value: Int { _value }
    func increment() { _value += 1 }
}

@Suite("HotkeyService integration with AppState")
@MainActor
struct HotkeyServiceTests {

    // MARK: - Basic hotkey flow

    @Test("hotkey down transitions to recording")
    func hotkeyDownRecording() {
        let state = AppState()
        state.handle(.hotkeyDown)
        #expect(state.dictationState.isRecording)
    }

    @Test("hotkey up after down transitions to transcribing")
    func hotkeyUpTranscribes() {
        let state = AppState()
        state.handle(.hotkeyDown)
        state.handle(.hotkeyUp)
        #expect(state.dictationState == .transcribing)
    }

    @Test("duplicate hotkey down is ignored")
    func duplicateDown() {
        let state = AppState()
        state.handle(.hotkeyDown)
        let handled = state.handle(.hotkeyDown)
        #expect(!handled)
        #expect(state.dictationState.isRecording)
    }

    @Test("hotkey down ignored during transcribing")
    func downIgnoredDuringTranscribing() {
        let state = AppState()
        state.handle(.hotkeyDown)
        state.handle(.hotkeyUp)
        let handled = state.handle(.hotkeyDown)
        #expect(!handled)
        #expect(state.dictationState == .transcribing)
    }

    @Test("hotkey down ignored during polishing")
    func downIgnoredDuringPolishing() {
        let state = AppState()
        state.handle(.hotkeyDown)
        state.handle(.hotkeyUp)
        state.handle(.transcriptionCompleted("test"))
        let handled = state.handle(.hotkeyDown)
        #expect(!handled)
    }

    @Test("hotkey down ignored during pasting")
    func downIgnoredDuringPasting() {
        let state = AppState()
        state.handle(.hotkeyDown)
        state.handle(.hotkeyUp)
        state.handle(.transcriptionCompleted("test"))
        state.handle(.polishCompleted("Test."))
        let handled = state.handle(.hotkeyDown)
        #expect(!handled)
    }

    // MARK: - Escape cancel

    @Test("escape during recording cancels")
    func escapeCancel() {
        let state = AppState()
        state.handle(.hotkeyDown)
        state.handle(.escapePressed)
        #expect(state.dictationState.isIdle)
    }

    @Test("escape when idle is ignored")
    func escapeIdleIgnored() {
        let state = AppState()
        let handled = state.handle(.escapePressed)
        #expect(!handled)
    }

    // MARK: - Max duration

    @Test("max duration stops recording and transcribes")
    func maxDuration() {
        let state = AppState()
        state.handle(.hotkeyDown)
        state.handle(.maxDurationReached)
        #expect(state.dictationState == .transcribing)
    }

    // MARK: - Shortcut capture

    @Test("begin capture enters awaiting state")
    func beginCapture() {
        let state = AppState()
        state.handle(.beginHotkeyCapture)
        #expect(state.dictationState == .awaitingHotkey)
    }

    @Test("capture done returns to idle")
    func captureDone() {
        let state = AppState()
        state.handle(.beginHotkeyCapture)
        state.handle(.hotkeyCaptureDone)
        #expect(state.dictationState.isIdle)
    }

    @Test("capture cancel returns to idle")
    func captureCancel() {
        let state = AppState()
        state.handle(.beginHotkeyCapture)
        state.handle(.cancelHotkeyCapture)
        #expect(state.dictationState.isIdle)
    }

    @Test("capture cannot begin when not idle")
    func captureNotWhenRecording() {
        let state = AppState()
        state.handle(.hotkeyDown)
        let handled = state.handle(.beginHotkeyCapture)
        #expect(!handled)
    }

    // MARK: - Permission blocking

    @Test("permission blocked from idle")
    func permissionBlocked() {
        let state = AppState()
        state.handle(.permissionBlocked(.microphone))
        #expect(state.dictationState == .blocked(.microphone))
    }

    @Test("permission resolved returns to idle")
    func permissionResolved() {
        let state = AppState()
        state.handle(.permissionBlocked(.accessibility))
        state.handle(.permissionResolved)
        #expect(state.dictationState.isIdle)
    }

    @Test("permission block ignored when recording")
    func permissionBlockIgnoredWhenRecording() {
        let state = AppState()
        state.handle(.hotkeyDown)
        let handled = state.handle(.permissionBlocked(.microphone))
        #expect(!handled)
    }

    // MARK: - Mock hotkey service

    @Test("mock hotkey service tracks start")
    func mockStart() {
        let mock = MockHotkeyService()
        mock.start(hotkey: .default) { _ in }
        #expect(mock.startCalled)
        #expect(mock.lastHotkey == .default)
    }

    @Test("mock hotkey service tracks capture")
    func mockCapture() {
        let mock = MockHotkeyService()
        mock.beginCapture()
        #expect(mock.isCapturing)
        mock.cancelCapture()
        #expect(!mock.isCapturing)
        #expect(mock.captureCancelled)
    }

    @Test("mock hotkey service updates hotkey")
    func mockUpdateHotkey() {
        let mock = MockHotkeyService()
        let newHotkey = Hotkey(keyCode: 36, modifiers: [.command, .shift])
        mock.updateHotkey(newHotkey)
        #expect(mock.lastHotkey == newHotkey)
    }

    @Test("mock hotkey service simulates events")
    func mockSimulate() {
        let mock = MockHotkeyService()
        let counter = SendableCounter()
        mock.start(hotkey: .default) { _ in
            counter.increment()
        }
        mock.simulateEvent(.hotkeyDown)
        mock.simulateEvent(.hotkeyUp)
        #expect(counter.value == 2)
    }
}
