import Foundation
import Testing
@testable import Uttr

@Suite("DictationState")
struct DictationStateTests {
    @Test("idle is the default state")
    func defaultState() {
        let state = DictationState.idle
        #expect(state == .idle)
    }

    @Test("recording state carries start date")
    func recordingCarriesDate() {
        let now = Date()
        let state = DictationState.recording(startedAt: now)
        #expect(state == .recording(startedAt: now))
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
}
