import Foundation
import OSLog

protocol DictationClock: Sendable {
    func sleep(for duration: TimeInterval) async throws
}

struct RealDictationClock: DictationClock {
    func sleep(for duration: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }
}

enum DictationMode: Sendable {
    case dictation
    case aiContent
}

@MainActor
final class DictationController {
    private let appState: AppState
    private let recorder: AudioRecording
    private let coordinator: TranscriptionCoordinator
    private let pasteService: PasteServicing
    private let clock: DictationClock
    private let metrics: DictationMetrics?
    private let localPolisherProvider: @MainActor () -> TextPolisher?
    private let cloudPolisherProvider: @MainActor () -> TextPolisher?
    private let aiProvider: @MainActor () -> AIContentGenerating?
    private let polishCoordinatorProvider: @MainActor () -> PolishCoordinator
    private let logger = Logger(subsystem: "com.uttr.app", category: "dictation")

    private var maxDurationTask: Task<Void, Never>?
    private var pipelineTask: Task<Void, Never>?
    private var attemptStartedAt = Date()
    private var currentMode: DictationMode = .dictation
    private var currentSessionID = UUID()

    init(
        appState: AppState,
        recorder: AudioRecording,
        coordinator: TranscriptionCoordinator,
        pasteService: PasteServicing,
        clock: DictationClock = RealDictationClock(),
        metrics: DictationMetrics? = nil,
        localPolisherProvider: @escaping @MainActor () -> TextPolisher? = { nil },
        cloudPolisherProvider: @escaping @MainActor () -> TextPolisher? = { nil },
        aiProvider: @escaping @MainActor () -> AIContentGenerating? = { nil },
        polishCoordinatorProvider: @escaping @MainActor () -> PolishCoordinator = { PolishCoordinator() }
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
        self.polishCoordinatorProvider = polishCoordinatorProvider
    }

    // MARK: - Hotkey entry points

    func recordingStarted(mode: DictationMode = .dictation) {
        currentMode = mode
        attemptStartedAt = Date()
        currentSessionID = UUID()
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

    func recordingEnded() {
        cancelMaxDurationTimer()
        pipelineTask = Task { [weak self] in
            await self?.finishDictation(hitMaxDuration: false)
        }
    }

    func recordingCancelled() {
        cancelMaxDurationTimer()
        currentSessionID = UUID()
        pipelineTask = Task { [weak self] in
            await self?.recorder.cancelRecording()
            self?.recordOutcome(.cancelled, polishOutcome: .cancelled)
        }
    }

    // MARK: - Pipeline

    private func finishDictation(hitMaxDuration: Bool) async {
        let releasedAt = Date()
        let sessionID = currentSessionID
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

        // Stage 1: local (offline) cleanup — always synchronous, never fails
        var localText = transcript
        if let polisher = localPolisherProvider() {
            do {
                let polished = try await polisher.polish(transcript)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !polished.isEmpty {
                    localText = polished
                }
            } catch {
                logger.error("Local polish failed open: \(error.localizedDescription, privacy: .public)")
            }
        }
        let localCleanAt = Date()

        // Stage 2: adaptive cloud polish — races against budget deadline
        let cloudPolisher = cloudPolisherProvider()
        let polishCoordinator = polishCoordinatorProvider()
        let polishResult = await polishCoordinator.polish(
            localText: localText,
            cloudPolisher: cloudPolisher,
            sessionID: sessionID)

        // Stale session guard: if a new dictation started while we polished,
        // this session's result must not paste.
        guard sessionID == currentSessionID else {
            logger.info("Session \(sessionID) superseded — discarding result")
            return
        }

        let finalText = polishResult.text
        if finalText == transcript {
            appState.handle(.polishFailed)
        } else {
            appState.handle(.polishCompleted(finalText))
        }

        let pasteStartedAt = Date()
        let pasted = await pasteService.paste(finalText)
        let pastedAt = Date()
        appState.handle(pasted ? .pasteCompleted : .pasteFailed)

        let polisherName: String? = {
            guard let cp = cloudPolisher else { return nil }
            return String(describing: type(of: cp))
        }()

        recordOutcome(
            pasted ? .completed : .pasteFailed,
            audio: audio,
            releasedAt: releasedAt,
            transcriptAt: transcriptAt,
            localCleanAt: localCleanAt,
            aiRequestStartedAt: polishResult.aiRequestStartedAt,
            aiResponseReceivedAt: polishResult.aiResponseReceivedAt,
            pasteStartedAt: pasteStartedAt,
            pastedAt: pastedAt,
            transcriptCharacters: finalText.count,
            hitMaxDuration: hitMaxDuration,
            polishOutcome: polishResult.outcome,
            polisherSelected: polisherName,
            configuredBudgetMs: polishCoordinator.budgetMs
        )
    }

    // MARK: - AI content stage

    private func runAIContent(
        prompt: String, audio: CapturedAudio,
        releasedAt: Date, transcriptAt: Date, hitMaxDuration: Bool
    ) async {
        guard let provider = aiProvider() else {
            logger.error("AI content requested but no provider is configured")
            DebugFileLog.append("dictation", "AI FAILED: no provider configured")
            appState.handle(.transcriptionFailed)
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
        localCleanAt: Date? = nil,
        aiRequestStartedAt: Date? = nil,
        aiResponseReceivedAt: Date? = nil,
        pasteStartedAt: Date? = nil,
        pastedAt: Date? = nil,
        transcriptCharacters: Int? = nil,
        hitMaxDuration: Bool = false,
        polishOutcome: PolishOutcome? = nil,
        polisherSelected: String? = nil,
        configuredBudgetMs: Int? = nil
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
            hitMaxDuration: hitMaxDuration,
            releaseToTranscriptMs: ms(releasedAt, transcriptAt),
            transcriptToLocalCleanMs: ms(transcriptAt, localCleanAt),
            localCleanToAiRequestMs: ms(localCleanAt, aiRequestStartedAt),
            aiRequestToResponseMs: ms(aiRequestStartedAt, aiResponseReceivedAt),
            responseToPasteMs: ms(aiResponseReceivedAt ?? localCleanAt, pasteStartedAt),
            releaseToPasteMs: ms(releasedAt, pastedAt),
            polishOutcome: polishOutcome,
            polisherSelected: polisherSelected,
            configuredBudgetMs: configuredBudgetMs,
            transcriptCharacters: transcriptCharacters
        ))
    }

    // MARK: - Max duration

    private func startMaxDurationTimer() {
        maxDurationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await clock.sleep(for: AudioPolicy.maximumDuration)
            } catch {
                return
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
