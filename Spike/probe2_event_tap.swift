// Spike Probe 2: Quartz event tap — Control-Option-Space key-down/key-up detection,
// key-repeat suppression, and tap-disable recovery.
// Establishes: (a) CGEvent.tapCreate succeeds once Input Monitoring is granted,
// (b) keyDown/keyUp/flagsChanged observation of the configured combo,
// (c) kCGEventTapDisabled* callbacks fire and the tap can be re-enabled.
// Run: swiftc -o /tmp/probe2 probe2_event_tap.swift && /tmp/probe2
// Hold Ctrl-Opt-Space a few times, press Ctrl-C to exit.

import CoreGraphics
import Foundation

let kSpaceKeyCode: Int64 = 49
let requiredFlags: CGEventFlags = [.maskControl, .maskAlternate]

final class TapBox: @unchecked Sendable { var tap: CFMachPort? }
let box = TapBox()

let mask: CGEventMask =
    (1 << CGEventType.keyDown.rawValue)
    | (1 << CGEventType.keyUp.rawValue)
    | (1 << CGEventType.flagsChanged.rawValue)

let callback: CGEventTapCallBack = { _, type, event, refcon in
    let box = Unmanaged<TapBox>.fromOpaque(refcon!).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        print("!! tap disabled (\(type.rawValue)) — re-enabling")
        if let tap = box.tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let flagsMatch = event.flags.contains(requiredFlags)

    if keyCode == kSpaceKeyCode && flagsMatch {
        switch type {
        case .keyDown where isRepeat:
            print("hotkey REPEAT (suppressed) — swallowing event")
            return nil // swallow so no space is typed
        case .keyDown:
            print("hotkey DOWN — would start recording; swallowing event")
            return nil
        case .keyUp:
            print("hotkey UP — would stop recording; swallowing event")
            return nil
        default: break
        }
    }
    return Unmanaged.passUnretained(event) // pass through everything else
}

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap, // active tap: allows swallowing the hotkey
    eventsOfInterest: mask,
    callback: callback,
    userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(box).toOpaque())
) else {
    print("CGEvent.tapCreate FAILED — Input Monitoring permission missing for this terminal")
    exit(1)
}
box.tap = tap

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
print("event tap active. Hold Control-Option-Space; Ctrl-C to quit.")
CFRunLoopRun()
