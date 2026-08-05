import CoreGraphics
import Foundation
import OSLog

enum HotkeyEvent: Sendable {
    case hotkeyDown
    case hotkeyUp
    case escapePressed
    case shortcutCaptured(keyCode: UInt16, modifiers: Set<ModifierKey>)
    case shortcutCaptureRejected(reason: String)
}

protocol HotkeyServiceProtocol: Sendable {
    func start(hotkey: Hotkey, callback: @escaping @Sendable (HotkeyEvent) -> Void)
    func stop()
    func updateHotkey(_ hotkey: Hotkey)
    func beginCapture()
    func cancelCapture()
}

final class EventTapHotkeyService: @unchecked Sendable, HotkeyServiceProtocol {
    private let logger = Logger(subsystem: "com.uttr.app", category: "hotkey")
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private let queue = DispatchQueue(label: "com.uttr.app.hotkey", qos: .userInteractive)

    private var currentHotkey: Hotkey = .default
    private var callback: (@Sendable (HotkeyEvent) -> Void)?
    private var isHotkeyHeld = false
    private var isCapturing = false

    private static let reservedShortcuts: Set<[UInt64]> = [
        [49, 0x100000],  // Cmd-Space (Spotlight)
        [49, 0x180000],  // Cmd-Shift-Space
        [12, 0x100000],  // Cmd-Q
        [13, 0x100000],  // Cmd-W
    ]

    // Fn/Globe virtual key code
    private static let fnKeyCode: UInt16 = 63

    func start(hotkey: Hotkey, callback: @escaping @Sendable (HotkeyEvent) -> Void) {
        self.currentHotkey = hotkey
        self.callback = callback

        queue.async { [weak self] in
            self?.installEventTap()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.removeEventTap()
        }
    }

    func updateHotkey(_ hotkey: Hotkey) {
        queue.async { [weak self] in
            self?.currentHotkey = hotkey
            self?.isHotkeyHeld = false
        }
    }

    func beginCapture() {
        queue.async { [weak self] in
            self?.isCapturing = true
            self?.isHotkeyHeld = false
        }
    }

    func cancelCapture() {
        queue.async { [weak self] in
            self?.isCapturing = false
        }
    }

    private func installEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<EventTapHotkeyService>.fromOpaque(refcon).takeUnretainedValue()
                return service.handleEvent(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            logger.error("Failed to create event tap — Input Monitoring permission likely missing")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source

        runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        logger.info("Event tap installed")
        CFRunLoopRun()
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource, let loop = runLoop {
            CFRunLoopRemoveSource(loop, source, .commonModes)
            CFRunLoopStop(loop)
        }
        eventTap = nil
        runLoopSource = nil
        runLoop = nil
        isHotkeyHeld = false
        logger.info("Event tap removed")
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                logger.warning("Event tap re-enabled after system disable")
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        if isCapturing {
            return handleCaptureEvent(type: type, keyCode: keyCode, flags: flags, event: event)
        }

        return handleHotkeyEvent(type: type, keyCode: keyCode, flags: flags, event: event)
    }

    private func handleHotkeyEvent(
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .keyDown && keyCode == 53 && isHotkeyHeld {
            isHotkeyHeld = false
            callback?(.escapePressed)
            return nil
        }

        let modifiersMatch = checkModifiers(flags, against: currentHotkey.modifiers)

        if type == .keyDown && keyCode == currentHotkey.keyCode && modifiersMatch {
            if isHotkeyHeld {
                return nil
            }
            isHotkeyHeld = true
            callback?(.hotkeyDown)
            return nil
        }

        if type == .keyUp && keyCode == currentHotkey.keyCode && isHotkeyHeld {
            isHotkeyHeld = false
            callback?(.hotkeyUp)
            return nil
        }

        if type == .flagsChanged && isHotkeyHeld {
            if !checkModifiers(flags, against: currentHotkey.modifiers) {
                isHotkeyHeld = false
                callback?(.hotkeyUp)
                return Unmanaged.passUnretained(event)
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleCaptureEvent(
        type: CGEventType,
        keyCode: UInt16,
        flags: CGEventFlags,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .keyDown && keyCode == 53 {
            isCapturing = false
            callback?(.shortcutCaptureRejected(reason: "Cancelled"))
            return nil
        }

        guard type == .keyUp else {
            return nil
        }

        if keyCode == Self.fnKeyCode {
            callback?(.shortcutCaptureRejected(
                reason: "The Fn/Globe key cannot be used as a shortcut because macOS reserves it at the system level."
            ))
            return nil
        }

        let modifiers = extractModifiers(from: flags)

        if modifiers.isEmpty {
            callback?(.shortcutCaptureRejected(reason: "Shortcut must include at least one modifier key (Control, Option, Command, or Shift)."))
            return nil
        }

        if isReservedShortcut(keyCode: keyCode, flags: flags) {
            callback?(.shortcutCaptureRejected(reason: "This shortcut is reserved by macOS."))
            return nil
        }

        isCapturing = false
        callback?(.shortcutCaptured(keyCode: keyCode, modifiers: modifiers))
        return nil
    }

    private func checkModifiers(_ flags: CGEventFlags, against required: Set<ModifierKey>) -> Bool {
        for mod in required {
            switch mod {
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

    private func extractModifiers(from flags: CGEventFlags) -> Set<ModifierKey> {
        var result = Set<ModifierKey>()
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        return result
    }

    private func isReservedShortcut(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        let modBits = flags.rawValue & 0x1F0000
        let key = [UInt64(keyCode), modBits]
        return Self.reservedShortcuts.contains(key)
    }

    deinit {
        removeEventTap()
    }
}
