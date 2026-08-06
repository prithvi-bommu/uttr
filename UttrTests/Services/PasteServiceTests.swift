import Foundation
import Testing
@testable import Uttr

// MARK: - ClipboardRestoreService

@Suite("ClipboardRestoreService")
@MainActor
struct ClipboardRestoreServiceTests {

    @Test("snapshot captures prior plain text")
    func snapshotCapturesText() {
        let pasteboard = MockPasteboard(initialText: "prior content")
        let service = ClipboardRestoreService(pasteboard: pasteboard)

        let snapshot = service.snapshot()

        #expect(snapshot.text == "prior content")
        #expect(snapshot.hadText)
    }

    @Test("snapshot of empty/non-text pasteboard captures nil")
    func snapshotCapturesNil() {
        let pasteboard = MockPasteboard(initialText: nil)
        let service = ClipboardRestoreService(pasteboard: pasteboard)

        let snapshot = service.snapshot()

        #expect(snapshot.text == nil)
        #expect(!snapshot.hadText)
    }

    @Test("restore writes prior text back when change count is still ours")
    func restoreWhenSafe() {
        let pasteboard = MockPasteboard(initialText: "prior")
        let service = ClipboardRestoreService(pasteboard: pasteboard)
        let snapshot = service.snapshot()
        let ourCount = service.write("transcript")

        let outcome = service.restoreIfSafe(snapshot, expectedChangeCount: ourCount)

        #expect(outcome == .restored)
        #expect(pasteboard.string() == "prior")
    }

    @Test("restore is skipped when another app changed the clipboard")
    func restoreSkippedOnExternalChange() {
        let pasteboard = MockPasteboard(initialText: "prior")
        let service = ClipboardRestoreService(pasteboard: pasteboard)
        let snapshot = service.snapshot()
        let ourCount = service.write("transcript")

        pasteboard.simulateExternalWrite("another app's content")

        let outcome = service.restoreIfSafe(snapshot, expectedChangeCount: ourCount)

        #expect(outcome == .skippedClipboardChanged)
        #expect(pasteboard.string() == "another app's content")
    }

    @Test("restore is skipped when the prior clipboard was empty or non-text")
    func restoreSkippedWithoutPriorText() {
        let pasteboard = MockPasteboard(initialText: nil)
        let service = ClipboardRestoreService(pasteboard: pasteboard)
        let snapshot = service.snapshot()
        let ourCount = service.write("transcript")

        let outcome = service.restoreIfSafe(snapshot, expectedChangeCount: ourCount)

        #expect(outcome == .skippedNoPriorText)
        // Transcript stays on the pasteboard — we never write non-text back.
        #expect(pasteboard.string() == "transcript")
    }
}

// MARK: - PasteService

@Suite("PasteService")
@MainActor
struct PasteServiceTests {

    struct Harness {
        let pasteboard: MockPasteboard
        let keyboard: MockKeyboardPoster
        let clock: MockDictationClock
        let service: PasteService
    }

    @MainActor
    private func makeHarness(priorClipboard: String?) -> Harness {
        let pasteboard = MockPasteboard(initialText: priorClipboard)
        let keyboard = MockKeyboardPoster()
        let clock = MockDictationClock()
        let service = PasteService(
            clipboard: ClipboardRestoreService(pasteboard: pasteboard),
            keyboard: keyboard,
            clock: clock
        )
        return Harness(
            pasteboard: pasteboard, keyboard: keyboard, clock: clock, service: service
        )
    }

    /// Drives the two suspended clock sleeps (50 ms propagation, 400 ms
    /// restore delay) and returns the paste result.
    @MainActor
    private func runPaste(
        _ h: Harness,
        text: String,
        betweenSleeps: @MainActor () -> Void = {}
    ) async -> Bool {
        let task = Task { await h.service.paste(text) }

        await waitUntil { h.clock.sleepCount == 1 }
        #expect(h.clock.sleepCount == 1)
        h.clock.fire()

        // Only wait for the second sleep if posting succeeded (a posting
        // failure returns before the 400 ms wait).
        if h.keyboard.succeed {
            await waitUntil { h.clock.sleepCount == 2 }
            #expect(h.clock.sleepCount == 2)
            betweenSleeps()
            h.clock.fire()
        }

        return await task.value
    }

    @Test("happy path: transcript pasted, prior text clipboard restored")
    func happyPathRestoresClipboard() async {
        let h = makeHarness(priorClipboard: "prior clipboard")

        let result = await runPaste(h, text: "the transcript")

        #expect(result)
        #expect(h.keyboard.postCount == 1)
        #expect(h.pasteboard.string() == "prior clipboard")
        #expect(h.pasteboard.setStringCalls == ["the transcript", "prior clipboard"])
        #expect(h.clock.requestedDurations == [
            PasteService.pasteboardPropagationDelay,
            PasteService.clipboardRestoreDelay
        ])
    }

    @Test("transcript is on the pasteboard before Command-V is posted")
    func transcriptWrittenBeforePost() async {
        let h = makeHarness(priorClipboard: "prior")
        var clipboardAtPostTime: String?
        h.keyboard.onPost = { clipboardAtPostTime = h.pasteboard.string() }

        let result = await runPaste(h, text: "the transcript")

        #expect(result)
        #expect(clipboardAtPostTime == "the transcript")
    }

    @Test("race: clipboard changed by another app during the wait is never overwritten")
    func externalClipboardChangeIsNotOverwritten() async {
        let h = makeHarness(priorClipboard: "prior")

        let result = await runPaste(h, text: "the transcript") {
            h.pasteboard.simulateExternalWrite("someone else's copy")
        }

        #expect(result)
        #expect(h.pasteboard.string() == "someone else's copy")
        // Exactly one write from us — the transcript; no restore write.
        #expect(h.pasteboard.setStringCalls == ["the transcript"])
    }

    @Test("non-text/empty prior clipboard: no restoration attempted, transcript remains")
    func nonTextClipboardIsNotRestored() async {
        let h = makeHarness(priorClipboard: nil)

        let result = await runPaste(h, text: "the transcript")

        #expect(result)
        #expect(h.pasteboard.string() == "the transcript")
        #expect(h.pasteboard.setStringCalls == ["the transcript"])
    }

    @Test("posting failure: returns false and leaves transcript on clipboard")
    func postFailureLeavesTextOnClipboard() async {
        let h = makeHarness(priorClipboard: "prior")
        h.keyboard.succeed = false

        let result = await runPaste(h, text: "the transcript")

        #expect(!result)
        #expect(h.keyboard.postCount == 1)
        // Transcript stays for manual Command-V; prior text is NOT restored.
        #expect(h.pasteboard.string() == "the transcript")
        // Only the 50 ms propagation wait happened — no 400 ms restore wait.
        #expect(h.clock.requestedDurations == [PasteService.pasteboardPropagationDelay])
    }

    @Test("paste failure routes AppState to idle with pasteFailedText set")
    func pasteFailureUpdatesAppState() {
        let appState = AppState()
        appState.handle(.hotkeyDown)
        appState.handle(.hotkeyUp)
        appState.handle(.transcriptionCompleted("the transcript"))
        appState.handle(.polishFailed)

        appState.handle(.pasteFailed)

        #expect(appState.dictationState == .idle)
        #expect(appState.pasteFailedText == "the transcript")
    }
}
