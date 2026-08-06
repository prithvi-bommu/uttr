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
/// Every attempt emits one redacted `DictationRecord` into `metrics`.
@MainActor
final class DictationController {
    private let appState: AppState
    private let recorder: AudioRecording
    private let coordinator: TranscriptionCoordinator
    private let pasteService: PasteServicing
    private let clock: DictationClock
    private let metrics: DictationMetrics?
    private let logger = Logger(subsystem: "com.uttr.app", category: "dictation")

    private var maxDurationTask: Task<Void, Never>?
    private var pipelineTask: Task<Void, Never>?
    private var attemptStartedAt = Date()

    init(
        appState: AppState,
        recorder: AudioRecording,
        coordinator: TranscriptionCoordinator,
        pasteService: PasteServicing,
        clock: DictationClock = RealDictationClock(),
        metrics: DictationMetrics? = nil
    ) {
        self.appState = appState
        self.recorder = recorder
        self.coordinator = coordinator
        self.pasteService = pasteService
        self.clock = clock
        self.metrics = metrics
    }

    // MARK: - Hotkey entry points (called by AppEnvironment after AppState transitions)

    /// Call after AppState accepted `.hotkeyDown` (state is now .recording).
    func recordingStarted() {
        attemptStartedAt = Date()
        pipelineTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await recorder.startRecording()
            } catch {
                logger.error("Recorder failed to start: \(error.localizedDescription, privacy: .public)")
                DebugFileLog.append("dictation", "Recorder FAILED to start: \(error.localizedDescription)")
                await recorder.cancelRecording()
                appState.handle(.recordingFailed)
                recordOutcome(.recorderFailed)
                return
            }
            startMaxDurationTimer()
        }
    }

    /// Call after AppState accepted `.hotkeyUp` (state is now .transcribing).
    func recordingEnded() {
        cancelMaxDurationTimer()
        pipelineTask = Task { [weak self] in
            await self?.finishDictation(hitMaxDuration: false)
        }
    }

    /// Call after AppState accepted `.escapePressed` (state returned to .idle).
    func recordingCancelled() {
        cancelMaxDurationTimer()
        pipelineTask = Task { [weak self] in
            await self?.recorder.cancelRecording()
            self?.recordOutcome(.cancelled)
        }
    }

    // MARK: - Pipeline

    private func finishDictation(hitMaxDuration: Bool) async {
        let releasedAt = Date()
        let audio = await recorder.stopRecording()
        DebugFileLog.append("dictation", "Captured \(String(format: "%.2f", audio.duration))s of audio")

        switch AudioPolicy.evaluate(audio) {
        case .tooShort:
            logger.info("Dictation rejected: too short (\(String(format: "%.2f", audio.duration), privacy: .public)s)")
            DebugFileLog.append("dictation", "REJECTED: too short")
            appState.handle(.noUsableAudio)
            recordOutcome(.rejectedTooShort, audio: audio, hitMaxDuration: hitMaxDuration)
            return
        case .noUsableAudio:
            logger.info("Dictation rejected: no meaningful samples")
            DebugFileLog.append("dictation", "REJECTED: no meaningful samples (mic silent? check Microphone permission)")
            appState.handle(.noUsableAudio)
            recordOutcome(.rejectedNoUsableAudio, audio: audio, hitMaxDuration: hitMaxDuration)
            return
        case .usable:
            break
        }

        let transcript: String
        do {
            transcript = try await coordinator.transcribe(audio)
        } catch {
            logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            DebugFileLog.append("dictation", "Transcription FAILED: \(error.localizedDescription)")
            appState.handle(.transcriptionFailed)
            recordOutcome(.transcriptionFailed, audio: audio, hitMaxDuration: hitMaxDuration)
            return
        }
        let transcriptAt = Date()

        guard !transcript.isEmpty else {
            logger.info("Empty transcript — nothing to paste")
            DebugFileLog.append("dictation", "Empty transcript — nothing to paste")
            appState.handle(.transcriptionFailed)
            recordOutcome(.emptyTranscript, audio: audio, releasedAt: releasedAt,
                          transcriptAt: transcriptAt, hitMaxDuration: hitMaxDuration)
            return
        }
        DebugFileLog.append("dictation", "Transcribed \(transcript.count) characters")

        appState.handle(.transcriptionCompleted(transcript))

        // Polish stage is M6; pass through unchanged. polishFailed routes
        // .polishing -> .pasting with the raw transcript per the state machine.
        appState.handle(.polishFailed)

        let pasted = await pasteService.paste(transcript)
        appState.handle(pasted ? .pasteCompleted : .pasteFailed)
        recordOutcome(pasted ? .completed : .pasteFailed,
                      audio: audio, releasedAt: releasedAt, transcriptAt: transcriptAt,
                      pastedAt: Date(), transcriptCharacters: transcript.count,
                      hitMaxDuration: hitMaxDuration)
    }

    // MARK: - Metrics

    private func recordOutcome(
        _ result: DictationRecord.Result,
        audio: CapturedAudio? = nil,
        releasedAt: Date? = nil,
        transcriptAt: Date? = nil,
        pastedAt: Date? = nil,
        transcriptCharacters: Int? = nil,
        hitMaxDuration: Bool = false
    ) {
        guard let metrics else { return }
        func ms(_ from: Date?, _ to: Date?) -> Int? {
            guard let from, let to else { return nil }
            return Int(to.timeIntervalSince(from) * 1000)
        }
        metrics.record(DictationRecord(
            startedAt: attemptStartedAt,
            engineID: coordinator.activeEngineID,
            result: result,
            audioDurationSeconds: audio?.duration ?? 0,
            releaseToTranscriptMs: ms(releasedAt, transcriptAt),
            releaseToPasteMs: ms(releasedAt, pastedAt),
            transcriptCharacters: transcriptCharacters,
            hitMaxDuration: hitMaxDuration
        ))
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
            await finishDictation(hitMaxDuration: true)
        }
    }

    private func cancelMaxDurationTimer() {
        maxDurationTask?.cancel()
        maxDurationTask = nil
    }
}
