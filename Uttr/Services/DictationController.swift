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

/// What a dictation's transcript is for.
enum DictationMode: Sendable {
    /// Normal dictation: transcript (optionally polished) is pasted.
    case dictation
    /// AI content: transcript is sent to the configured AI backend as a
    /// prompt and the *response* is pasted.
    case aiContent
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
    /// Returns a local text polisher when offline cleanup is enabled in
    /// settings, or nil to skip polishing. Evaluated per dictation so a
    /// settings change takes effect immediately without rebuilding the
    /// controller. Defaults to "never polish" for tests and older call sites.
    private let localPolisherProvider: @MainActor () -> TextPolisher?
    /// Returns the optional cloud polisher selected in settings. Cloud polish
    /// runs after local cleanup and fails open to the latest local transcript.
    private let cloudPolisherProvider: @MainActor () -> TextPolisher?
    /// Returns the AI backend when AI-content mode is enabled and configured,
    /// or nil to fail the AI dictation. Evaluated per dictation.
    private let aiProvider: @MainActor () -> AIContentGenerating?
    private let logger = Logger(subsystem: "com.uttr.app", category: "dictation")

    private var maxDurationTask: Task<Void, Never>?
    private var pipelineTask: Task<Void, Never>?
    private var attemptStartedAt = Date()
    /// Mode of the dictation currently in flight. Set by `recordingStarted`.
    private var currentMode: DictationMode = .dictation

    init(
        appState: AppState,
        recorder: AudioRecording,
        coordinator: TranscriptionCoordinator,
        pasteService: PasteServicing,
        clock: DictationClock = RealDictationClock(),
        metrics: DictationMetrics? = nil,
        localPolisherProvider: @escaping @MainActor () -> TextPolisher? = { nil },
        cloudPolisherProvider: @escaping @MainActor () -> TextPolisher? = { nil },
        aiProvider: @escaping @MainActor () -> AIContentGenerating? = { nil }
    ) {
        self.appState = appState
        self.recorder = recorder
        self.coordinator = coordinator
        self.pasteService = pasteService
        self.clock = clock
        self.metrics = metrics
        self.localPolisherProvider = localPolisherProvider
        self.cloudPolisherProvider = cloudPolisherProvider
        self.aiProvider = aiProvider
    }

    // MARK: - Hotkey entry points (called by AppEnvironment after AppState transitions)

    /// Call after AppState accepted `.hotkeyDown` (state is now .recording).
    func recordingStarted(mode: DictationMode = .dictation) {
        currentMode = mode
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

        // Short-but-usable clips are padded to a full decode window so the
        // model isn't handed a sub-window it will drop or garble.
        let decodeAudio = AudioPolicy.rightPadded(audio)

        let transcript: String
        do {
            transcript = try await coordinator.transcribe(decodeAudio)
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

        if currentMode == .aiContent {
            await runAIContent(prompt: transcript, audio: audio,
                               releasedAt: releasedAt, transcriptAt: transcriptAt,
                               hitMaxDuration: hitMaxDuration)
            return
        }

        appState.handle(.transcriptionCompleted(transcript))

        // Optional local cleanup followed by optional cloud polish. Each stage
        // fails open to the latest usable transcript.
        var finalText = transcript
        let polishers = [localPolisherProvider(), cloudPolisherProvider()].compactMap { $0 }
        for polisher in polishers {
            do {
                let polished = try await polisher.polish(finalText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !polished.isEmpty {
                    finalText = polished
                }
            } catch {
                logger.error("Text polish failed open: \(error.localizedDescription, privacy: .public)")
            }
        }
        if finalText == transcript {
            appState.handle(.polishFailed)
        } else {
            appState.handle(.polishCompleted(finalText))
        }

        let pasted = await pasteService.paste(finalText)
        appState.handle(pasted ? .pasteCompleted : .pasteFailed)
        recordOutcome(pasted ? .completed : .pasteFailed,
                      audio: audio, releasedAt: releasedAt, transcriptAt: transcriptAt,
                      pastedAt: Date(), transcriptCharacters: finalText.count,
                      hitMaxDuration: hitMaxDuration)
    }

    // MARK: - AI content stage

    /// Sends the spoken prompt to the configured AI backend and pastes the
    /// response. Only the transcribed text leaves the machine, never audio.
    /// Failures return to idle without pasting anything.
    private func runAIContent(
        prompt: String, audio: CapturedAudio,
        releasedAt: Date, transcriptAt: Date, hitMaxDuration: Bool
    ) async {
        guard let provider = aiProvider() else {
            logger.error("AI content requested but no provider is configured")
            DebugFileLog.append("dictation", "AI FAILED: no provider configured")
            appState.handle(.transcriptionFailed) // transcribing -> idle
            recordOutcome(.transcriptionFailed, audio: audio, hitMaxDuration: hitMaxDuration)
            return
        }

        appState.handle(.aiRequestStarted)
        let response: String
        do {
            response = try await provider.generate(prompt: prompt)
        } catch {
            logger.error("AI request failed: \(error.localizedDescription, privacy: .public)")
            DebugFileLog.append("dictation", "AI FAILED: \(error.localizedDescription)")
            appState.handle(.aiRequestFailed)
            recordOutcome(.transcriptionFailed, audio: audio, hitMaxDuration: hitMaxDuration)
            return
        }

        appState.handle(.aiResponseReceived(response))
        let pasted = await pasteService.paste(response)
        appState.handle(pasted ? .pasteCompleted : .pasteFailed)
        recordOutcome(pasted ? .completed : .pasteFailed,
                      audio: audio, releasedAt: releasedAt, transcriptAt: transcriptAt,
                      pastedAt: Date(), transcriptCharacters: response.count,
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
