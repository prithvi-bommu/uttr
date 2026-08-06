import CoreGraphics
import Foundation

/// A keyboard event as seen by the event tap, reduced to what the hotkey
/// logic needs. Pure data so the processor is unit-testable without CGEvents.
struct KeyEventInput: Sendable {
    enum Kind: Sendable {
        case keyDown
        case keyUp
        case flagsChanged
    }

    let kind: Kind
    let keyCode: UInt16
    let flags: CGEventFlags
}

/// What the event tap should do with an event after processing.
enum HotkeyProcessorAction: Equatable, Sendable {
    /// Pass the event through to the system unchanged.
    case pass
    /// Consume the event (it must not reach the focused app).
    case swallow
    /// Deliver `event` to the app; `swallow` says whether to also consume it.
    case emit(HotkeyEvent, swallow: Bool)
}

/// Pure decision logic for the global event tap: hold-to-talk matching,
/// Escape cancel, shortcut capture, and bare Fn/Globe support (ADR-008).
///
/// Extracted from `EventTapHotkeyService` so it can be mutated synchronously
/// under a lock (the tap's run-loop thread blocks its serial queue forever,
/// so `queue.async` mutations never ran — the M2 rebinding defect) and unit
/// tested directly.
struct HotkeyEventProcessor {
    static let escapeKeyCode: UInt16 = 53

    private static let reservedShortcuts: Set<[UInt64]> = [
        [49, 0x100000],  // Cmd-Space (Spotlight)
        [49, 0x120000],  // Cmd-Shift-Space
        [12, 0x100000],  // Cmd-Q
        [13, 0x100000],  // Cmd-W
    ]

    private(set) var hotkey: Hotkey
    private(set) var isHotkeyHeld = false
    private(set) var isCapturing = false

    /// Candidate combo sampled at key-DOWN so modifier release order at the
    /// end of the capture gesture cannot falsely reject it.
    private var captureCandidate: (keyCode: UInt16, modifiers: Set<ModifierKey>)?
    /// True while a bare Fn press is the current capture candidate.
    private var fnCaptureCandidate = false

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    // MARK: - External state changes (call under the service's lock)

    mutating func updateHotkey(_ newHotkey: Hotkey) {
        hotkey = newHotkey
        isHotkeyHeld = false
    }

    mutating func beginCapture() {
        isCapturing = true
        isHotkeyHeld = false
        captureCandidate = nil
        fnCaptureCandidate = false
    }

    mutating func cancelCapture() {
        isCapturing = false
        captureCandidate = nil
        fnCaptureCandidate = false
    }

    // MARK: - Event processing

    mutating func process(_ input: KeyEventInput) -> HotkeyProcessorAction {
        isCapturing ? processCapture(input) : processHotkey(input)
    }

    // MARK: - Normal hold-to-talk mode

    private mutating func processHotkey(_ input: KeyEventInput) -> HotkeyProcessorAction {
        if input.kind == .keyDown && input.keyCode == Self.escapeKeyCode && isHotkeyHeld {
            isHotkeyHeld = false
            return .emit(.escapePressed, swallow: true)
        }

        if hotkey.isFnGlobe {
            return processBareFnHotkey(input)
        }

        let modifiersMatch = Self.checkModifiers(input.flags, against: hotkey.modifiers)

        if input.kind == .keyDown && input.keyCode == hotkey.keyCode && modifiersMatch {
            if isHotkeyHeld {
                return .swallow // key repeat
            }
            isHotkeyHeld = true
            return .emit(.hotkeyDown, swallow: true)
        }

        if input.kind == .keyUp && input.keyCode == hotkey.keyCode && isHotkeyHeld {
            isHotkeyHeld = false
            return .emit(.hotkeyUp, swallow: true)
        }

        if input.kind == .flagsChanged && isHotkeyHeld {
            if !Self.checkModifiers(input.flags, against: hotkey.modifiers) {
                isHotkeyHeld = false
                return .emit(.hotkeyUp, swallow: false)
            }
        }

        return .pass
    }

    /// Bare Fn/Globe hold-to-talk (ADR-008). The Fn key surfaces only as
    /// `flagsChanged` with keyCode 63; `.maskSecondaryFn` is set while held.
    /// Events are passed through — with the system Globe action set to
    /// "Do Nothing" there is no side effect, and swallowing modifier-state
    /// events could corrupt other apps' modifier tracking.
    private mutating func processBareFnHotkey(_ input: KeyEventInput) -> HotkeyProcessorAction {
        guard input.kind == .flagsChanged && input.keyCode == Hotkey.fnGlobeKeyCode else {
            return .pass
        }

        let fnDown = input.flags.contains(.maskSecondaryFn)

        if fnDown && !isHotkeyHeld {
            isHotkeyHeld = true
            return .emit(.hotkeyDown, swallow: false)
        }
        if !fnDown && isHotkeyHeld {
            isHotkeyHeld = false
            return .emit(.hotkeyUp, swallow: false)
        }
        return .pass
    }

    // MARK: - Shortcut capture mode

    private mutating func processCapture(_ input: KeyEventInput) -> HotkeyProcessorAction {
        switch input.kind {
        case .keyDown:
            if input.keyCode == Self.escapeKeyCode {
                cancelCapture()
                return .emit(.shortcutCaptureRejected(reason: "Cancelled"), swallow: true)
            }
            // Sample the combo now, while the modifiers are physically held.
            fnCaptureCandidate = false
            captureCandidate = (input.keyCode, Self.extractModifiers(from: input.flags))
            return .swallow

        case .keyUp:
            guard let candidate = captureCandidate, input.keyCode == candidate.keyCode else {
                return .swallow // stale key-up from before capture began
            }
            return finishCapture(with: candidate)

        case .flagsChanged:
            // Bare Fn/Globe capture (ADR-008): press sets the candidate,
            // release completes it — unless a normal key was pressed meanwhile.
            if input.keyCode == Hotkey.fnGlobeKeyCode {
                if input.flags.contains(.maskSecondaryFn) {
                    fnCaptureCandidate = true
                    captureCandidate = nil
                } else if fnCaptureCandidate {
                    cancelCapture()
                    return .emit(
                        .shortcutCaptured(keyCode: Hotkey.fnGlobeKeyCode, modifiers: []),
                        swallow: false
                    )
                }
            }
            return .pass
        }
    }

    private mutating func finishCapture(
        with candidate: (keyCode: UInt16, modifiers: Set<ModifierKey>)
    ) -> HotkeyProcessorAction {
        // Every terminal outcome must leave capture mode; a lingering
        // isCapturing would swallow the entire keyboard.
        cancelCapture()

        if candidate.modifiers.isEmpty {
            return .emit(.shortcutCaptureRejected(
                reason: "Shortcut must include at least one modifier key (Control, Option, Command, or Shift)."
            ), swallow: true)
        }
        if Self.isReservedShortcut(keyCode: candidate.keyCode, modifiers: candidate.modifiers) {
            return .emit(.shortcutCaptureRejected(
                reason: "This shortcut is reserved by macOS."
            ), swallow: true)
        }
        return .emit(
            .shortcutCaptured(keyCode: candidate.keyCode, modifiers: candidate.modifiers),
            swallow: true
        )
    }

    // MARK: - Helpers

    static func checkModifiers(_ flags: CGEventFlags, against required: Set<ModifierKey>) -> Bool {
        for modifier in required {
            switch modifier {
            case .control:
                if !flags.contains(.maskControl) { return false }
            case .option:
                if !flags.contains(.maskAlternate) { return false }
            case .command:
                if !flags.contains(.maskCommand) { return false }
            case .shift:
                if !flags.contains(.maskShift) { return false }
            }
        }
        return true
    }

    static func extractModifiers(from flags: CGEventFlags) -> Set<ModifierKey> {
        var result = Set<ModifierKey>()
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        return result
    }

    private static func isReservedShortcut(keyCode: UInt16, modifiers: Set<ModifierKey>) -> Bool {
        var modBits: UInt64 = 0
        if modifiers.contains(.command) { modBits |= CGEventFlags.maskCommand.rawValue }
        if modifiers.contains(.shift) { modBits |= CGEventFlags.maskShift.rawValue }
        if modifiers.contains(.control) { modBits |= CGEventFlags.maskControl.rawValue }
        if modifiers.contains(.option) { modBits |= CGEventFlags.maskAlternate.rawValue }
        return reservedShortcuts.contains([UInt64(keyCode), modBits])
    }
}
