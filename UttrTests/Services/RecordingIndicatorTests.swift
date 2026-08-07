import Foundation
import Testing
@testable import Uttr

@Suite("RecordingIndicator")
@MainActor
struct RecordingIndicatorTests {

    @Test("AppState invokes onStateChange for accepted transitions only")
    func stateHookFires() {
        let appState = AppState()
        var seen: [DictationState] = []
        appState.onStateChange = { seen.append($0) }

        appState.handle(.hotkeyDown)         // idle -> recording (accepted)
        appState.handle(.hotkeyDown)         // recording -> recording (rejected)
        appState.handle(.hotkeyUp)           // recording -> transcribing (accepted)
        appState.handle(.transcriptionFailed) // transcribing -> idle (accepted)

        #expect(seen.count == 3)
        #expect(seen[0].isRecording)
        #expect(seen[1] == .transcribing)
        #expect(seen[2] == .idle)
    }

    @Test("waveform bar height scales with level and stays within bounds")
    func waveformBounds() {
        #expect(WaveformBars.height(level: 0, weight: 1) == 4)      // floor at silence
        #expect(WaveformBars.height(level: 1, weight: 1) == 18)     // ceiling at max
        #expect(WaveformBars.height(level: 0.5, weight: 1) == 11)   // linear midpoint
        #expect(WaveformBars.height(level: 5, weight: 1) == 18)     // clamped above 1
        #expect(WaveformBars.height(level: -1, weight: 1) == 4)     // clamped below 0
        // Weighted bars stay below the full-weight bar at the same level.
        #expect(WaveformBars.height(level: 0.8, weight: 0.5) < WaveformBars.height(level: 0.8, weight: 1))
    }

    @Test("mock recorder reports zero level by default (protocol extension)")
    func defaultLevel() async {
        let recorder = MockAudioRecorder()
        let level = await recorder.currentAudioLevel()
        #expect(level == 0)
    }
}
