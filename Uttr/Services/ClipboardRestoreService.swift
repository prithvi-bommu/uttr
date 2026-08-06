import AppKit
import Foundation

/// Snapshot of the pasteboard's plain-text state taken before a paste
/// (spec §9 step 1). Text-only by design: non-text clipboard content
/// (images, files) is never captured and therefore never restored.
struct ClipboardSnapshot: Equatable, Sendable {
    /// Prior plain-text content; nil when the pasteboard was empty or
    /// held non-text data.
    let text: String?

    var hadText: Bool { text != nil }
}

/// Minimal pasteboard seam so unit tests never touch the user's real
/// clipboard (spec §12).
@MainActor
protocol Pasteboarding {
    /// The pasteboard's current change count. Increments whenever any
    /// process writes to the pasteboard.
    var changeCount: Int { get }

    /// Current plain-text contents, or nil if empty/non-text.
    func string() -> String?

    /// Replaces the pasteboard contents with `text`.
    /// - Returns: the change count produced by this write.
    @discardableResult
    func setString(_ text: String) -> Int
}

/// Production adapter over `NSPasteboard.general`.
@MainActor
struct GeneralPasteboard: Pasteboarding {
    var changeCount: Int { NSPasteboard.general.changeCount }

    func string() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    @discardableResult
    func setString(_ text: String) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }
}

/// Result of a restore attempt, for logging and tests.
enum ClipboardRestoreOutcome: Equatable, Sendable {
    /// Prior text was written back to the pasteboard.
    case restored
    /// Another app changed the pasteboard after our write — never overwrite it.
    case skippedClipboardChanged
    /// The prior clipboard was empty or non-text — nothing to restore
    /// (documented product limitation, spec §9).
    case skippedNoPriorText
}

/// The snapshot/restore half of the paste sequence (spec §9 steps 1 and 6).
/// Restore is race-safe: it only writes if the pasteboard change count still
/// equals the value produced by our own write.
@MainActor
struct ClipboardRestoreService {
    private let pasteboard: Pasteboarding

    init(pasteboard: Pasteboarding = GeneralPasteboard()) {
        self.pasteboard = pasteboard
    }

    /// Step 1: capture prior plain-text clipboard content (if any).
    func snapshot() -> ClipboardSnapshot {
        ClipboardSnapshot(text: pasteboard.string())
    }

    /// Step 2: write the transcript to the pasteboard.
    /// - Returns: our change count, used later to detect external writes.
    func write(_ text: String) -> Int {
        pasteboard.setString(text)
    }

    /// Step 6: restore the snapshot if and only if no other app wrote to the
    /// pasteboard since our write (`changeCount` unchanged) and the prior
    /// content was plain text.
    @discardableResult
    func restoreIfSafe(
        _ snapshot: ClipboardSnapshot,
        expectedChangeCount: Int
    ) -> ClipboardRestoreOutcome {
        guard pasteboard.changeCount == expectedChangeCount else {
            return .skippedClipboardChanged
        }
        guard let priorText = snapshot.text else {
            return .skippedNoPriorText
        }
        pasteboard.setString(priorText)
        return .restored
    }
}
