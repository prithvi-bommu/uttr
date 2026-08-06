import CoreGraphics
import Foundation
import OSLog

/// Delivery of final text into the focused app.
protocol PasteServicing: Sendable {
    /// Delivers `text` to the focused application.
    /// - Returns: true when delivery is believed successful. On false, the
    ///   text has been left on the clipboard for manual Command-V.
    func paste(_ text: String) async -> Bool
}

/// Seam for posting the synthetic Command-V so unit tests never post real
/// keyboard events (spec §12).
@MainActor
protocol KeyboardPosting {
    /// Posts Command-V key-down + key-up to the HID event tap.
    /// - Returns: true when both events were created and posted.
    func postCommandV() -> Bool
}

/// Production Command-V poster via CoreGraphics (spec §9 step 4 — never
/// AppleScript or a shell command). Requires Accessibility permission;
/// without it `CGEvent` creation fails and this returns false.
@MainActor
struct CGKeyboardPoster: KeyboardPosting {
    /// ANSI "V" virtual key code.
    private static let vKeyCode: CGKeyCode = 9

    func postCommandV() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let keyDown = CGEvent(
                keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: false
            )
        else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}

/// Real cross-application paste (M4). Implements the exact spec §9 sequence:
/// 1. Snapshot plain-text clipboard content only.
/// 2. Write final text to the general pasteboard.
/// 3. Wait 50 ms for pasteboard propagation.
/// 4. Post Command-V via CoreGraphics.
/// 5. Wait 400 ms.
/// 6. Restore the prior text clipboard iff the change count still equals the
///    value from our write. Never restore non-text; never overwrite another
///    app's newer clipboard content.
///
/// On event-posting failure the transcript intentionally stays on the
/// clipboard (no restore) so the user can paste manually; the caller surfaces
/// the `Text copied — paste with Command-V.` status via `.pasteFailed`.
/// Deliberately never logs transcript contents (privacy contract §11).
@MainActor
final class PasteService: PasteServicing {
    static let pasteboardPropagationDelay: TimeInterval = 0.05
    static let clipboardRestoreDelay: TimeInterval = 0.4

    private let clipboard: ClipboardRestoreService
    private let keyboard: KeyboardPosting
    private let clock: DictationClock
    private let logger = Logger(subsystem: "com.uttr.app", category: "paste")

    init(
        clipboard: ClipboardRestoreService = ClipboardRestoreService(),
        keyboard: KeyboardPosting = CGKeyboardPoster(),
        clock: DictationClock = RealDictationClock()
    ) {
        self.clipboard = clipboard
        self.keyboard = keyboard
        self.clock = clock
    }

    func paste(_ text: String) async -> Bool {
        let snapshot = clipboard.snapshot()
        let ourChangeCount = clipboard.write(text)

        try? await clock.sleep(for: Self.pasteboardPropagationDelay)

        guard keyboard.postCommandV() else {
            logger.error("Command-V posting failed — leaving text on clipboard for manual paste")
            DebugFileLog.append("paste", "Command-V posting FAILED — text left on clipboard (Accessibility permission?)")
            return false
        }

        try? await clock.sleep(for: Self.clipboardRestoreDelay)

        let outcome = clipboard.restoreIfSafe(snapshot, expectedChangeCount: ourChangeCount)
        logger.info("Paste posted (\(text.count, privacy: .public) characters, restore: \(String(describing: outcome), privacy: .public))")
        DebugFileLog.append("paste", "Paste posted (\(text.count) characters, restore: \(String(describing: outcome)))")
        return true
    }
}
