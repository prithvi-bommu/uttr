import CoreGraphics
import Foundation
import OSLog

enum HotkeyEvent: Equatable, Sendable {
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

/// Owns the long-lived Quartz event tap on a dedicated run-loop thread and
/// delegates all decisions to `HotkeyEventProcessor`.
///
/// Threading model (the M2 rebinding fix): `installEventTap()` parks its
/// serial queue's thread inside `CFRunLoopRun()` forever, so that queue can
/// never execute another block. All mutable state therefore lives in the
/// lock-protected `processor` and is mutated *synchronously* from whatever
/// thread calls `updateHotkey`/`beginCapture`/`cancelCapture`; the tap
/// callback reads and mutates it under the same lock.
final class EventTapHotkeyService: @unchecked Sendable, HotkeyServiceProtocol {
    private let logger = Logger(subsystem: "com.uttr.app", category: "hotkey")
    private let queue = DispatchQueue(label: "com.uttr.app.hotkey", qos: .userInteractive)
    private let lock = NSLock()

    // Guarded by `lock`
    private var processor = HotkeyEventProcessor(hotkey: .default)
    private var callback: (@Sendable (HotkeyEvent) -> Void)?
    private var runLoop: CFRunLoop?

    // Written once on the tap thread during install; read for re-enable/stop.
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start(hotkey: Hotkey, callback: @escaping @Sendable (HotkeyEvent) -> Void) {
        lock.withLock {
            processor = HotkeyEventProcessor(hotkey: hotkey)
            self.callback = callback
        }
        queue.async { [weak self] in
            self?.installEventTap()
        }
    }

    func stop() {
        // CFRunLoopStop is thread-safe; never dispatch onto `queue` — its
        // only thread is parked inside CFRunLoopRun.
        let loop: CFRunLoop? = lock.withLock { runLoop }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let loop {
            CFRunLoopStop(loop)
        }
        lock.withLock {
            runLoop = nil
        }
        eventTap = nil
        runLoopSource = nil
        logger.info("Event tap stopped")
    }

    func updateHotkey(_ hotkey: Hotkey) {
        lock.withLock {
            processor.updateHotkey(hotkey)
        }
    }

    func beginCapture() {
        lock.withLock {
            processor.beginCapture()
        }
    }

    func cancelCapture() {
        lock.withLock {
            processor.cancelCapture()
        }
    }

    // MARK: - Tap installation (runs on `queue`'s thread, which then parks in the run loop)

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

        let loop = CFRunLoopGetCurrent()
        lock.withLock {
            runLoop = loop
        }
        CFRunLoopAddSource(loop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        logger.info("Event tap installed")
        CFRunLoopRun()
    }

    // MARK: - Event handling (runs on the tap's run-loop thread)

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                logger.warning("Event tap re-enabled after system disable")
            }
            return Unmanaged.passUnretained(event)
        }

        let kind: KeyEventInput.Kind
        switch type {
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .flagsChanged: kind = .flagsChanged
        default: return Unmanaged.passUnretained(event)
        }

        let input = KeyEventInput(
            kind: kind,
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags
        )

        // Mutate under the lock; invoke the callback outside it.
        let (action, cb): (HotkeyProcessorAction, (@Sendable (HotkeyEvent) -> Void)?) = lock.withLock {
            (processor.process(input), callback)
        }

        switch action {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .swallow:
            return nil
        case .emit(let hotkeyEvent, let swallow):
            cb?(hotkeyEvent)
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
    }

    deinit {
        stop()
    }
}
