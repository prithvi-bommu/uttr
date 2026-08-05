import Foundation
import Testing
@testable import Uttr

@Suite("DictationState")
struct DictationStateTests {
    @Test("idle is the default state")
    func defaultState() {
        let state = DictationState.idle
        #expect(state == .idle)
        #expect(state.isIdle)
    }

    @Test("recording state carries start date")
    func recordingCarriesDate() {
        let now = Date()
        let state = DictationState.recording(startedAt: now)
        #expect(state == .recording(startedAt: now))
        #expect(state.isRecording)
        #expect(!state.isIdle)
    }

    @Test("blocked states are distinguishable")
    func blockedStatesDistinguishable() {
        let mic = DictationState.blocked(.microphone)
        let input = DictationState.blocked(.inputMonitoring)
        let accessibility = DictationState.blocked(.accessibility)
        #expect(mic != input)
        #expect(input != accessibility)
        #expect(mic != accessibility)
    }

    @Test("all states are equatable")
    func allStatesEquatable() {
        #expect(DictationState.idle == .idle)
        #expect(DictationState.transcribing == .transcribing)
        #expect(DictationState.polishing == .polishing)
        #expect(DictationState.pasting == .pasting)
        #expect(DictationState.awaitingHotkey == .awaitingHotkey)
    }

    @Test("status text for each state")
    func statusText() {
        #expect(DictationState.idle.statusText == "Ready")
        #expect(DictationState.transcribing.statusText == "Transcribing…")
        #expect(DictationState.polishing.statusText == "Polishing…")
        #expect(DictationState.pasting.statusText == "Pasting…")
        #expect(DictationState.awaitingHotkey.statusText == "Press your shortcut…")
        #expect(DictationState.blocked(.microphone).statusText == "Microphone permission required")
    }

    @Test("menu bar icon varies by state")
    func menuBarIcon() {
        #expect(DictationState.idle.menuBarIcon == "mic.circle")
        #expect(DictationState.recording(startedAt: Date()).menuBarIcon == "mic.circle.fill")
        #expect(DictationState.transcribing.menuBarIcon == "ellipsis.circle")
        #expect(DictationState.blocked(.microphone).menuBarIcon == "exclamationmark.triangle")
    }
}
