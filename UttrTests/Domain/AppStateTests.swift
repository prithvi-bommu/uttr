import Foundation
import Testing
@testable import Uttr

@Suite("AppState")
@MainActor
struct AppStateTests {

    // MARK: - Happy path transitions

    @Test("idle -> recording on hotkey down")
    func hotkeyDownStartsRecording() {
        let state = AppState()
        let handled = state.handle(.hotkeyDown)
        #expect(handled)
        #expect(state.dictationState.isRecording)
    }

    @Test("recording -> transcribing on hotkey up")
    func hotkeyUpStartsTranscribing() {
        let state = AppState()
        state.handle(.hotkeyDown)
        let handled = state.handle(.hotkeyUp)
        #expect(handled)
        #expect(state.dictationState == .transcribing)
    }

    @Test("transcribing -> idle on no usable audio (post-release rejection)")
    func noUsableAudioAfterReleaseReturnsToIdle() {
        // Regression: audio validation runs after hotkey release, so the
        // rejection arrives in .transcribing. Before the fix this event was
        // ignored and the app was stuck in .transcribing, silently ignoring
        // every subsequent hotkey press.
        let state = AppState()
        state.handle(.hotkeyDown)
        state.handle(.hotkeyUp)
        #expect(state.dictationState == .transcribing)
        let handled = state.handle(.noUsableAudio)
        #expect(handled)
        #expect(state.dictationState == .idle)
        // And the next dictation must start normally.
        #expect(state.handle(.hotkeyDown))
        #expect(state.dictationState.isRecording)
    }

    @Test("transcribing -> polishing on transcription completed")
    func transcriptionCompletedGoesToPolishing() {
        let state = AppState()
        state.handle(.hotkeyDown)
        state.handle(.hotkeyUp)
        let handled = state.handle(.transcriptionCompleted("Hello world"))
        #expect(handled)
        #expect(state.dictationState == .polishing)
        #expect(state.lastTranscript == "Hello world")
    }

    @Test("polishing -> pasting on polish completed")
    func polishCompletedGoesToPasting() {
        let state = AppState()
        state.handle(.hotkeyDown)
        state.handle(.hotkeyUp)
        state.handle(.transcriptionCompleted("hello"))
        let handled = state.handle(.polishCompleted("Hello."))
        #expect(handled)
        #expect(state.dictationState == .pasting)
        #expect(state.lastTranscript == "Hello.")
    }

    @Test("pasting -> idle on paste completed")
    func pasteCompletedReturnsToIdle() {
        let state = AppState()
        state.handle(.hotkeyDown)
        state.handle(.hotkeyUp)
        state.handle(.transcriptionCompleted("hello"))
        state.handle(.polishCompleted("Hello."))
        let handled = state.handle(.pasteCompleted)
        #expect(handled)
        #expect(state.dictationState.isIdle)
        #expect(state.pasteFailedText == nil)
    }

    @Test("full path without polish: idle -> recording -> transcribing -> pasting -> idle")
    func pathWithoutPolish() {
        let state = AppState()
        state.handle(.hotkeyDown)
        state.handle(.hotkeyUp)
        state.handle(.transcriptionCompleted("hello"))
        state.handle(.polishFailed)
        #expect(state.dictationState == .pasting)
        state.handle(.pasteCompleted)
        #expect(state.dictationState.isIdle)
    }

    // MARK: - Cancel and error transitions

    @Test("escape during recording cancels to idle")
    func escapeCancelsRecording() {
        let state = AppState()
        state.handle(.hotkeyDown)
        let handled = state.handle(.escapePressed)
        #expect(handled)
        #expect(state.dictationState.isIdle)
        #expect(state.lastTranscript == nil)
    }

    @Test("recording failure returns to idle")
    func recordingFailureReturnsToIdle() {
        let state = AppState()
        state.handle(.hotkeyDown)
        let handled = state.handle(.recordingFailed)
        #expect(handled)
        #expect(state.dictationState.isIdle)
    }

    @Test("no usable audio returns to idle")
    func noUsableAudioReturnsToIdle() {
        let state = AppState()
        state.handle(.hotkeyDown)
        let handled = state.handle(.noUsableAudio)
        #expect(handled)
        #expect(state.dictationState.isIdle)
    }

    @Test("transcription failure returns to idle")
    func transcriptionFailureReturnsToIdle() {
        let state = AppState()
        state.handle(.hotkeyDown)
        state.handle(.hotkeyUp)
        let handled = state.handle(.transcriptionFailed)
        #expect(handled)
        #expect(state.dictationState.isIdle)
    }

    @Test("paste failure returns to idle with failed text")
    func pasteFailureReturnsToIdle() {
        let state = AppState()
        state.handle(.hotkeyDown)
        state.handle(.hotkeyUp)
        state.handle(.transcriptionCompleted("hello"))
        state.handle(.polishCompleted("Hello."))
        let handled = state.handle(.pasteFailed)
        #expect(handled)
        #expect(state.dictationState.isIdle)
        #expect(state.pasteFailedText == "Hello.")
    }

    @Test("max duration stops recording and begins transcribing")
    func maxDurationTransition() {
        let state = AppState()
        state.handle(.hotkeyDown)
        let handled = state.handle(.maxDurationReached)
        #expect(handled)
        #expect(state.dictationState == .transcribing)
    }

    // MARK: - Duplicate and invalid transitions

    @Test("hotkey down ignored when not idle")
    func hotkeyDownIgnoredWhenRecording() {
        let state = AppState()
        state.handle(.hotkeyDown)
        let handled = state.handle(.hotkeyDown)
        #expect(!handled)
        #expect(state.dictationState.isRecording)
    }

    @Test("hotkey down ignored during transcribing")
    func hotkeyDownIgnoredDuringTranscribing() {
        let state = AppState()
        state.handle(.hotkeyDown)
        state.handle(.hotkeyUp)
        let handled = state.handle(.hotkeyDown)
        #expect(!handled)
    }

    @Test("hotkey up ignored when idle")
    func hotkeyUpIgnoredWhenIdle() {
        let state = AppState()
        let handled = state.handle(.hotkeyUp)
        #expect(!handled)
    }

    @Test("escape ignored when idle")
    func escapeIgnoredWhenIdle() {
        let state = AppState()
        let handled = state.handle(.escapePressed)
        #expect(!handled)
    }

    // MARK: - Hotkey capture

    @Test("idle -> awaitingHotkey -> idle")
    func hotkeyCapture() {
        let state = AppState()
        state.handle(.beginHotkeyCapture)
        #expect(state.dictationState == .awaitingHotkey)
        state.handle(.hotkeyCaptureDone)
        #expect(state.dictationState.isIdle)
    }

    @Test("cancel hotkey capture returns to idle")
    func cancelHotkeyCapture() {
        let state = AppState()
        state.handle(.beginHotkeyCapture)
        state.handle(.cancelHotkeyCapture)
        #expect(state.dictationState.isIdle)
    }

    // MARK: - Permission blocking

    @Test("idle -> blocked -> idle")
    func permissionBlocking() {
        let state = AppState()
        state.handle(.permissionBlocked(.microphone))
        #expect(state.dictationState == .blocked(.microphone))
        state.handle(.permissionResolved)
        #expect(state.dictationState.isIdle)
    }

    // MARK: - Settings mutability

    @Test("settings can change when idle")
    func settingsChangeableWhenIdle() {
        let state = AppState()
        #expect(state.canChangeSettings)
    }

    @Test("settings cannot change when recording")
    func settingsNotChangeableWhenRecording() {
        let state = AppState()
        state.handle(.hotkeyDown)
        #expect(!state.canChangeSettings)
    }

    @Test("settings cannot change when transcribing")
    func settingsNotChangeableWhenTranscribing() {
        let state = AppState()
        state.handle(.hotkeyDown)
        state.handle(.hotkeyUp)
        #expect(!state.canChangeSettings)
    }
}
