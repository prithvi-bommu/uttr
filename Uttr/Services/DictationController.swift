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

        guard rejectUnusableAudio(audio, hitMaxDuration: hitMaxDuration) == nil else {
            return
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
        let context = PipelineContext(
            audio: audio, sessionID: sessionID,
            releasedAt: releasedAt, transcriptAt: transcriptAt,
            hitMaxDuration: hitMaxDuration)
        await polishAndPaste(transcript: transcript, context: context)
    }

    private struct PipelineContext {
        let audio: CapturedAudio
        let sessionID: UUID
        let releasedAt: Date
        let transcriptAt: Date
        let hitMaxDuration: Bool
    }

    private func rejectUnusableAudio(
        _ audio: CapturedAudio, hitMaxDuration: Bool
    ) -> DictationRecord.Result? {
        switch AudioPolicy.evaluate(audio) {
        case .tooShort:
            logger.info("Dictation rejected: too short")
            DebugFileLog.append("dictation", "REJECTED: too short")
            appState.handle(.noUsableAudio)
            recordOutcome(.rejectedTooShort, audio: audio, hitMaxDuration: hitMaxDuration)
            return .rejectedTooShort
        case .noUsableAudio:
            logger.info("Dictation rejected: no meaningful samples")
            DebugFileLog.append("dictation", "REJECTED: no meaningful samples")
            appState.handle(.noUsableAudio)
            recordOutcome(.rejectedNoUsableAudio, audio: audio, hitMaxDuration: hitMaxDuration)
            return .rejectedNoUsableAudio
        case .usable:
            return nil
        }
    }

    private func polishAndPaste(transcript: String, context: PipelineContext) async {
        let localText = await applyLocalPolish(transcript)
        let localCleanAt = Date()

        let cloudPolisher = cloudPolisherProvider()
        let polishCoord = polishCoordinatorProvider()
        let polishResult = await polishCoord.polish(
            localText: localText, cloudPolisher: cloudPolisher,
            sessionID: context.sessionID)

        guard context.sessionID == currentSessionID else {
            logger.info("Session \(context.sessionID) superseded — discarding result")
            return
        }

        let finalText = polishResult.text
        appState.handle(finalText == transcript ? .polishFailed : .polishCompleted(finalText))

        let pasteStartedAt = Date()
        let pasted = await pasteService.paste(finalText)
        appState.handle(pasted ? .pasteCompleted : .pasteFailed)

        recordOutcome(
            pasted ? .completed : .pasteFailed,
            audio: context.audio, releasedAt: context.releasedAt,
            transcriptAt: context.transcriptAt, localCleanAt: localCleanAt,
            aiRequestStartedAt: polishResult.aiRequestStartedAt,
            aiResponseReceivedAt: polishResult.aiResponseReceivedAt,
            pasteStartedAt: pasteStartedAt, pastedAt: Date(),
            transcriptCharacters: finalText.count,
            hitMaxDuration: context.hitMaxDuration,
            polishOutcome: polishResult.outcome,
            polisherSelected: cloudPolisher.map { String(describing: type(of: $0)) },
            configuredBudgetMs: polishCoord.budgetMs)
    }

    private func applyLocalPolish(_ transcript: String) async -> String {
        guard let polisher = localPolisherProvider() else { return transcript }
        do {
            let polished = try await polisher.polish(transcript)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return polished.isEmpty ? transcript : polished
        } catch {
            logger.error("Local polish failed open: \(error.localizedDescription, privacy: .public)")
            return transcript
        }
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
