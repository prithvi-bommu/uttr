// Spike Probe 3: Synthetic Command-V into the focused app (TextEdit) after
// Accessibility permission, plus race-safe clipboard restore via changeCount.
// Establishes: (a) AXIsProcessTrusted gate, (b) NSPasteboard write + changeCount,
// (c) CGEvent keyboard post of Cmd-V, (d) 400ms-delayed restore only if
// changeCount is still ours.
// Run: swiftc -o /tmp/probe3 probe3_paste.swift && open -a TextEdit && /tmp/probe3
// Click into a TextEdit document within 3 seconds of launching the probe.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// (a) Accessibility trust check — required for posting keyboard events.
let trusted = AXIsProcessTrusted()
print("AXIsProcessTrusted: \(trusted)")
guard trusted else {
    print("Grant Accessibility to the terminal app in System Settings → Privacy → Accessibility, then re-run")
    exit(1)
}

print("Focus a TextEdit document now — pasting in 3 seconds…")
Thread.sleep(forTimeInterval: 3)

let pb = NSPasteboard.general

// (b) Snapshot prior plain-text clipboard (text-only policy).
let priorText = pb.string(forType: .string)
print("prior clipboard text: \(priorText.map { "\"\($0.prefix(40))\"" } ?? "<none/non-text>")")

pb.clearContents()
pb.setString("Uttr spike probe paste \(Date())", forType: .string)
let ourChangeCount = pb.changeCount
print("wrote transcript to pasteboard, changeCount=\(ourChangeCount)")

// Pasteboard propagation delay per spec.
Thread.sleep(forTimeInterval: 0.05)

// (c) Synthetic Command-V via CoreGraphics.
let src = CGEventSource(stateID: .combinedSessionState)
let vKeyCode: CGKeyCode = 9
let down = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true)
let up = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false)
down?.flags = .maskCommand
up?.flags = .maskCommand
down?.post(tap: .cghidEventTap)
up?.post(tap: .cghidEventTap)
print("posted Cmd-V")

// (d) Restore after 400 ms only if nobody else touched the clipboard.
Thread.sleep(forTimeInterval: 0.4)
if pb.changeCount == ourChangeCount {
    if let priorText {
        pb.clearContents()
        pb.setString(priorText, forType: .string)
        print("restored prior text clipboard")
    } else {
        print("no prior text clipboard — leaving pasteboard as-is (spec: no non-text restore)")
    }
} else {
    print("changeCount moved (\(pb.changeCount) != \(ourChangeCount)) — another app changed clipboard; NOT restoring")
}
print("check TextEdit: the probe text should be pasted at the cursor")
