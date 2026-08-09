import CoreGraphics
import Foundation
import Testing
@testable import Uttr

// MARK: - Hotkey processor: second (AI) hotkey

@Suite("HotkeyEventProcessor AI hotkey")
struct AIHotkeyProcessorTests {

    private let optionA = Hotkey(keyCode: 0, modifiers: [.option]) // ⌥A
    private let primary = Hotkey(keyCode: 49, modifiers: [.control, .option]) // ⌃⌥Space

    private func makeProcessor() -> HotkeyEventProcessor {
        var processor = HotkeyEventProcessor(hotkey: primary)
        processor.updateAIHotkey(optionA)
        return processor
    }

    @Test("AI hotkey down/up emits AI events")
    func aiDownUp() {
        var p = makeProcessor()
        let down = p.process(KeyEventInput(kind: .keyDown, keyCode: 0, flags: .maskAlternate))
        #expect(down == .emit(.aiHotkeyDown, swallow: true))
        #expect(p.isAIHotkeyHeld)
        let up = p.process(KeyEventInput(kind: .keyUp, keyCode: 0, flags: .maskAlternate))
        #expect(up == .emit(.aiHotkeyUp, swallow: true))
        #expect(!p.isAIHotkeyHeld)
    }

    @Test("primary hotkey still works with AI hotkey registered")
    func primaryStillWorks() {
        var p = makeProcessor()
        let flags: CGEventFlags = [.maskControl, .maskAlternate]
        let down = p.process(KeyEventInput(kind: .keyDown, keyCode: 49, flags: flags))
        #expect(down == .emit(.hotkeyDown, swallow: true))
        let up = p.process(KeyEventInput(kind: .keyUp, keyCode: 49, flags: flags))
        #expect(up == .emit(.hotkeyUp, swallow: true))
    }

    @Test("AI hotkey ignored while primary is held (mutual exclusion)")
    func mutualExclusionPrimaryFirst() {
        var p = makeProcessor()
        _ = p.process(KeyEventInput(kind: .keyDown, keyCode: 49, flags: [.maskControl, .maskAlternate]))
        #expect(p.isHotkeyHeld)
        let aiDown = p.process(KeyEventInput(kind: .keyDown, keyCode: 0, flags: .maskAlternate))
        #expect(aiDown == .pass || aiDown == .swallow) // never emits aiHotkeyDown
        #expect(!p.isAIHotkeyHeld)
    }

    @Test("primary hotkey ignored while AI is held (mutual exclusion)")
    func mutualExclusionAIFirst() {
        var p = makeProcessor()
        _ = p.process(KeyEventInput(kind: .keyDown, keyCode: 0, flags: .maskAlternate))
        #expect(p.isAIHotkeyHeld)
        let primaryDown = p.process(
            KeyEventInput(kind: .keyDown, keyCode: 49, flags: [.maskControl, .maskAlternate]))
        #expect(primaryDown == .pass)
        #expect(!p.isHotkeyHeld)
    }

    @Test("escape cancels a held AI hotkey")
    func escapeCancelsAI() {
        var p = makeProcessor()
        _ = p.process(KeyEventInput(kind: .keyDown, keyCode: 0, flags: .maskAlternate))
        let esc = p.process(KeyEventInput(kind: .keyDown, keyCode: 53, flags: []))
        #expect(esc == .emit(.escapePressed, swallow: true))
        #expect(!p.isAIHotkeyHeld)
    }

    @Test("releasing the modifier ends the AI hold")
    func modifierReleaseEndsAIHold() {
        var p = makeProcessor()
        _ = p.process(KeyEventInput(kind: .keyDown, keyCode: 0, flags: .maskAlternate))
        let release = p.process(KeyEventInput(kind: .flagsChanged, keyCode: 58, flags: []))
        #expect(release == .emit(.aiHotkeyUp, swallow: false))
        #expect(!p.isAIHotkeyHeld)
    }

    @Test("bare-Fn AI hotkey is refused")
    func bareFnRefused() {
        var p = HotkeyEventProcessor(hotkey: primary)
        p.updateAIHotkey(Hotkey(keyCode: Hotkey.fnGlobeKeyCode, modifiers: []))
        #expect(p.aiHotkey == nil)
    }

    @Test("nil clears the AI hotkey")
    func nilClears() {
        var p = makeProcessor()
        p.updateAIHotkey(nil)
        let down = p.process(KeyEventInput(kind: .keyDown, keyCode: 0, flags: .maskAlternate))
        #expect(down == .pass)
    }
}

// MARK: - State machine

@Suite("AppState prompting transitions")
@MainActor
struct AIStateMachineTests {

    @Test("transcribing -> prompting -> pasting on success")
    func happyPath() {
        let s = AppState()
        s.handle(.hotkeyDown)
        s.handle(.hotkeyUp)
        #expect(s.dictationState == .transcribing)
        #expect(s.handle(.aiRequestStarted))
        #expect(s.dictationState == .prompting)
        #expect(s.handle(.aiResponseReceived("generated text")))
        #expect(s.dictationState == .pasting)
        #expect(s.lastTranscript == "generated text")
    }

    @Test("prompting -> idle on failure, nothing pasted")
    func failurePath() {
        let s = AppState()
        s.handle(.hotkeyDown)
        s.handle(.hotkeyUp)
        s.handle(.aiRequestStarted)
        #expect(s.handle(.aiRequestFailed))
        #expect(s.dictationState == .idle)
    }

    @Test("aiRequestStarted is rejected outside transcribing")
    func rejectedWhenIdle() {
        let s = AppState()
        #expect(!s.handle(.aiRequestStarted))
        #expect(s.dictationState == .idle)
    }
}

// MARK: - Provider response parsing (pure)

@Suite("AIContent providers")
struct AIProviderParsingTests {

    @Test("parses OpenAI chat completion content")
    func openAIParse() throws {
        let body = """
        {"choices":[{"message":{"role":"assistant","content":"  Hello there.  "}}]}
        """.data(using: .utf8)!
        #expect(try OpenAICompatibleProvider.extractText(from: body) == "Hello there.")
    }

    @Test("OpenAI empty content throws emptyResponse")
    func openAIEmpty() {
        let body = #"{"choices":[{"message":{"content":"   "}}]}"#.data(using: .utf8)!
        #expect(throws: AIContentError.self) {
            _ = try OpenAICompatibleProvider.extractText(from: body)
        }
    }

    @Test("parses Anthropic message content")
    func anthropicParse() throws {
        let body = """
        {"content":[{"type":"text","text":"Response body"}],"role":"assistant"}
        """.data(using: .utf8)!
        #expect(try AnthropicProvider.extractText(from: body) == "Response body")
    }

    @Test("error detail extracted from provider error JSON")
    func errorDetail() {
        let body = #"{"error":{"message":"invalid api key"}}"#.data(using: .utf8)!
        #expect(OpenAICompatibleProvider.errorDetail(from: body) == "invalid api key")
    }
}

// MARK: - Controller AI pipeline

@Suite("DictationController AI mode")
@MainActor
struct AIControllerTests {

    final class MockAIProvider: AIContentGenerating, @unchecked Sendable {
        var response = "generated content"
        var error: Error?
        private(set) var receivedPrompts: [String] = []

        func generate(prompt: String) async throws -> String {
            receivedPrompts.append(prompt)
            if let error { throw error }
            return response
        }
    }

    private func makeHarness(ai: MockAIProvider?) -> (AppState, MockAudioRecorder, MockEngineFactory, MockPasteService, DictationController) {
        let appState = AppState()
        let recorder = MockAudioRecorder()
        let factory = MockEngineFactory()
        let coordinator = TranscriptionCoordinator(
            factory: factory,
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: false))
        coordinator.configure(selection: .whisperKit, whisperModel: "small.en")
        let pasteService = MockPasteService()
        let controller = DictationController(
            appState: appState, recorder: recorder, coordinator: coordinator,
            pasteService: pasteService, clock: MockDictationClock(),
            aiProvider: { ai })
        return (appState, recorder, factory, pasteService, controller)
    }

    @Test("AI mode sends transcript as prompt and pastes the response")
    func aiHappyPath() async {
        let ai = MockAIProvider()
        let (appState, recorder, factory, pasteService, controller) = makeHarness(ai: ai)
        factory.whisperEngine.transcriptToReturn = "write a haiku about rain"

        appState.handle(.hotkeyDown)
        controller.recordingStarted(mode: .aiContent)
        await waitUntil { recorder.startCount == 1 }
        appState.handle(.hotkeyUp)
        controller.recordingEnded()

        await waitUntil { appState.dictationState == .idle && !pasteService.pastedTexts.isEmpty }
        #expect(ai.receivedPrompts == ["write a haiku about rain"])
        #expect(pasteService.pastedTexts == ["generated content"])
        #expect(appState.lastTranscript == "generated content")
    }

    @Test("AI failure returns to idle without pasting")
    func aiFailure() async {
        let ai = MockAIProvider()
        ai.error = AIContentError.requestFailed(status: 401, detail: "bad key")
        let (appState, recorder, factory, pasteService, controller) = makeHarness(ai: ai)
        factory.whisperEngine.transcriptToReturn = "some prompt"

        appState.handle(.hotkeyDown)
        controller.recordingStarted(mode: .aiContent)
        await waitUntil { recorder.startCount == 1 }
        appState.handle(.hotkeyUp)
        controller.recordingEnded()

        await waitUntil { appState.dictationState == .idle }
        #expect(pasteService.pastedTexts.isEmpty)
    }

    @Test("no provider configured fails cleanly to idle")
    func noProvider() async {
        let (appState, recorder, factory, pasteService, controller) = makeHarness(ai: nil)
        factory.whisperEngine.transcriptToReturn = "some prompt"

        appState.handle(.hotkeyDown)
        controller.recordingStarted(mode: .aiContent)
        await waitUntil { recorder.startCount == 1 }
        appState.handle(.hotkeyUp)
        controller.recordingEnded()

        await waitUntil { appState.dictationState == .idle }
        #expect(pasteService.pastedTexts.isEmpty)
    }

    @Test("dictation mode is unaffected by an AI provider being available")
    func dictationUnaffected() async {
        let ai = MockAIProvider()
        let (appState, recorder, factory, pasteService, controller) = makeHarness(ai: ai)
        factory.whisperEngine.transcriptToReturn = "plain dictation"

        appState.handle(.hotkeyDown)
        controller.recordingStarted(mode: .dictation)
        await waitUntil { recorder.startCount == 1 }
        appState.handle(.hotkeyUp)
        controller.recordingEnded()

        await waitUntil { appState.dictationState == .idle && !pasteService.pastedTexts.isEmpty }
        #expect(pasteService.pastedTexts == ["plain dictation"])
        #expect(ai.receivedPrompts.isEmpty)
    }
}
