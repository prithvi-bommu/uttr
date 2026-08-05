import Foundation
import OSLog

/// Injectable clock for the max-duration timer so tests don't sleep.
protocol DictationClock: Sendable {
    func sleep(for duration: TimeInterval) async throws
}

struct RealDictationClock: DictationClock {
    func sleep(for duration: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }
}

/// Drives the dictation transaction around `AppState`:
/// hotkey down → start capture (+120 s limit timer)
/// hotkey up   → stop capture → validate → transcribe → (polish M6) → paste
/// escape      → cancel capture, no paste
/// Every failure path returns AppState to `.idle` via the events it emits.
@MainActor
final class DictationController {
    private let appState: AppState
    private let recorder: AudioRecording
    private let coordinator: TranscriptionCoordinator
    private let pasteService: PasteServicing
    private let clock: DictationClock
    private let logger = Logger(subsystem: "com.uttr.app", category: "dictation")

    private var maxDurationTask: Task<Void, Never>?
    private var pipelineTask: Task<Void, Never>?

    init(
        appState: AppState,
        recorder: AudioRecording,
        coordinator: TranscriptionCoordinator,
        pasteService: PasteServicing,
        clock: DictationClock = RealDictationClock()
    ) {
        self.appState = appState
        self.recorder = recorder
        self.coordinator = coordinator
        self.pasteService = pasteService
        self.clock = clock
    }

    // MARK: - Hotkey entry points (called by AppEnvironment after AppState transitions)

    /// Call after AppState accepted `.hotkeyDown` (state is now .recording).
    func recordingStarted() {
        pipelineTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await recorder.startRecording()
            } catch {
                logger.error("Recorder failed to start: \(error.localizedDescription, privacy: .public)")
                await recorder.cancelRecording()
                appState.handle(.recordingFailed)
                return
            }
            startMaxDurationTimer()
        }
    }

    /// Call after AppState accepted `.hotkeyUp` (state is now .transcribing).
    func recordingEnded() {
        cancelMaxDurationTimer()
        pipelineTask = Task { [weak self] in
            await self?.finishDictation()
        }
    }

    /// Call after AppState accepted `.escapePressed` (state returned to .idle).
    func recordingCancelled() {
        cancelMaxDurationTimer()
        pipelineTask = Task { [weak self] in
            await self?.recorder.cancelRecording()
        }
    }

    // MARK: - Pipeline

    private func finishDictation() async {
        let audio = await recorder.stopRecording()

        switch AudioPolicy.evaluate(audio) {
        case .tooShort:
            logger.info("Dictation rejected: too short (\(String(format: "%.2f", audio.duration), privacy: .public)s)")
            appState.handle(.noUsableAudio)
            return
        case .noUsableAudio:
            logger.info("Dictation rejected: no meaningful samples")
            appState.handle(.noUsableAudio)
            return
        case .usable:
            break
        }

        let transcript: String
        do {
            transcript = try await coordinator.transcribe(audio)
        } catch {
            logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            appState.handle(.transcriptionFailed)
            return
        }

        guard !transcript.isEmpty else {
            logger.info("Empty transcript — nothing to paste")
            appState.handle(.transcriptionFailed)
            return
        }

        appState.handle(.transcriptionCompleted(transcript))

        // Polish stage is M6; pass through unchanged. polishFailed routes
        // .polishing -> .pasting with the raw transcript per the state machine.
        appState.handle(.polishFailed)

        let pasted = await pasteService.paste(transcript)
        appState.handle(pasted ? .pasteCompleted : .pasteFailed)
    }

    // MARK: - Max duration (spec §8: stop at 120 s and transcribe what we have)

    private func startMaxDurationTimer() {
        maxDurationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await clock.sleep(for: AudioPolicy.maximumDuration)
            } catch {
                return // cancelled — normal release beat the limit
            }
            guard appState.dictationState.isRecording else { return }
            logger.info("Max recording duration reached — stopping and transcribing")
            appState.handle(.maxDurationReached)
            await finishDictation()
        }
    }

    private func cancelMaxDurationTimer() {
        maxDurationTask?.cancel()
        maxDurationTask = nil
    }
}
