import CoreGraphics
import Foundation
import Testing
@testable import Uttr

@Suite("HotkeyEventProcessor")
struct HotkeyEventProcessorTests {

    private func keyDown(_ keyCode: UInt16, flags: CGEventFlags = []) -> KeyEventInput {
        KeyEventInput(kind: .keyDown, keyCode: keyCode, flags: flags)
    }

    private func keyUp(_ keyCode: UInt16, flags: CGEventFlags = []) -> KeyEventInput {
        KeyEventInput(kind: .keyUp, keyCode: keyCode, flags: flags)
    }

    private func flagsChanged(_ keyCode: UInt16, flags: CGEventFlags) -> KeyEventInput {
        KeyEventInput(kind: .flagsChanged, keyCode: keyCode, flags: flags)
    }

    private let ctrlOpt: CGEventFlags = [.maskControl, .maskAlternate]

    // MARK: - Hold-to-talk matching (regression: existing behavior preserved)

    @Test("default hotkey down/up emits hotkeyDown then hotkeyUp, swallowed")
    func holdToTalk() {
        var p = HotkeyEventProcessor(hotkey: .default)

        #expect(p.process(keyDown(49, flags: ctrlOpt)) == .emit(.hotkeyDown, swallow: true))
        #expect(p.isHotkeyHeld)
        #expect(p.process(keyUp(49, flags: ctrlOpt)) == .emit(.hotkeyUp, swallow: true))
        #expect(!p.isHotkeyHeld)
    }

    @Test("key repeat while held is swallowed without a second hotkeyDown")
    func repeatSuppressed() {
        var p = HotkeyEventProcessor(hotkey: .default)
        _ = p.process(keyDown(49, flags: ctrlOpt))

        #expect(p.process(keyDown(49, flags: ctrlOpt)) == .swallow)
    }

    @Test("escape while held emits escapePressed and releases the hold")
    func escapeCancels() {
        var p = HotkeyEventProcessor(hotkey: .default)
        _ = p.process(keyDown(49, flags: ctrlOpt))

        #expect(p.process(keyDown(53)) == .emit(.escapePressed, swallow: true))
        #expect(!p.isHotkeyHeld)
    }

    @Test("releasing a required modifier while held emits hotkeyUp")
    func modifierReleaseEndsHold() {
        var p = HotkeyEventProcessor(hotkey: .default)
        _ = p.process(keyDown(49, flags: ctrlOpt))

        let action = p.process(flagsChanged(59, flags: [.maskAlternate])) // control released
        #expect(action == .emit(.hotkeyUp, swallow: false))
    }

    @Test("unrelated keys pass through")
    func unrelatedKeysPass() {
        var p = HotkeyEventProcessor(hotkey: .default)
        #expect(p.process(keyDown(4, flags: [])) == .pass)
        #expect(p.process(keyUp(4, flags: [])) == .pass)
    }

    // MARK: - updateHotkey (regression: rebinding must take effect)

    @Test("updateHotkey rebinds matching to the new combination")
    func updateHotkeyTakesEffect() {
        var p = HotkeyEventProcessor(hotkey: .default)
        p.updateHotkey(Hotkey(keyCode: 2, modifiers: [.command, .shift])) // Cmd-Shift-D

        // Old hotkey no longer matches.
        #expect(p.process(keyDown(49, flags: ctrlOpt)) == .pass)
        // New hotkey matches.
        let action = p.process(keyDown(2, flags: [.maskCommand, .maskShift]))
        #expect(action == .emit(.hotkeyDown, swallow: true))
    }

    // MARK: - Shortcut capture

    @Test("capture: combo sampled at keyDown, emitted at keyUp")
    func captureHappyPath() {
        var p = HotkeyEventProcessor(hotkey: .default)
        p.beginCapture()

        #expect(p.process(keyDown(2, flags: [.maskCommand, .maskShift])) == .swallow)
        let action = p.process(keyUp(2, flags: [.maskCommand, .maskShift]))

        #expect(action == .emit(
            .shortcutCaptured(keyCode: 2, modifiers: [.command, .shift]), swallow: true
        ))
        #expect(!p.isCapturing)
    }

    @Test("capture: modifiers released before the key still capture correctly")
    func captureToleratesReleaseOrder() {
        var p = HotkeyEventProcessor(hotkey: .default)
        p.beginCapture()

        _ = p.process(keyDown(2, flags: [.maskCommand, .maskShift]))
        // User lets go of both modifiers first — flags empty at keyUp.
        _ = p.process(flagsChanged(56, flags: [.maskCommand]))
        _ = p.process(flagsChanged(55, flags: []))
        let action = p.process(keyUp(2, flags: []))

        #expect(action == .emit(
            .shortcutCaptured(keyCode: 2, modifiers: [.command, .shift]), swallow: true
        ))
    }

    @Test("capture: modifier-less key is rejected AND capture mode ends")
    func captureRejectionEndsCapture() {
        var p = HotkeyEventProcessor(hotkey: .default)
        p.beginCapture()

        _ = p.process(keyDown(4, flags: []))
        let action = p.process(keyUp(4, flags: []))

        guard case .emit(.shortcutCaptureRejected, let swallow) = action else {
            Issue.record("Expected rejection, got \(action)")
            return
        }
        #expect(swallow)
        // Regression: rejection must exit capture mode or the keyboard stays swallowed.
        #expect(!p.isCapturing)
        #expect(p.process(keyDown(4, flags: [])) == .pass)
    }

    @Test("capture: reserved Cmd-Space is rejected")
    func captureRejectsReserved() {
        var p = HotkeyEventProcessor(hotkey: .default)
        p.beginCapture()

        _ = p.process(keyDown(49, flags: [.maskCommand]))
        let action = p.process(keyUp(49, flags: [.maskCommand]))

        guard case .emit(.shortcutCaptureRejected, _) = action else {
            Issue.record("Expected rejection, got \(action)")
            return
        }
        #expect(!p.isCapturing)
    }

    @Test("capture: escape cancels and exits capture mode")
    func captureEscapeCancels() {
        var p = HotkeyEventProcessor(hotkey: .default)
        p.beginCapture()

        let action = p.process(keyDown(53))
        #expect(action == .emit(.shortcutCaptureRejected(reason: "Cancelled"), swallow: true))
        #expect(!p.isCapturing)
    }

    @Test("capture: stale keyUp from before capture began is ignored")
    func captureIgnoresStaleKeyUp() {
        var p = HotkeyEventProcessor(hotkey: .default)
        p.beginCapture()

        // keyUp with no prior keyDown candidate (e.g. releasing the mouse-click key).
        #expect(p.process(keyUp(36, flags: [])) == .swallow)
        #expect(p.isCapturing)
    }

    // MARK: - Bare Fn/Globe (ADR-008)

    @Test("Fn capture: press and release Fn alone captures the bare Fn hotkey")
    func fnCapture() {
        var p = HotkeyEventProcessor(hotkey: .default)
        p.beginCapture()

        #expect(p.process(flagsChanged(63, flags: [.maskSecondaryFn])) == .pass)
        let action = p.process(flagsChanged(63, flags: []))

        #expect(action == .emit(
            .shortcutCaptured(keyCode: Hotkey.fnGlobeKeyCode, modifiers: []), swallow: false
        ))
        #expect(!p.isCapturing)
    }

    @Test("Fn capture candidate is discarded when a normal key follows")
    func fnCandidateDiscardedByNormalKey() {
        var p = HotkeyEventProcessor(hotkey: .default)
        p.beginCapture()

        _ = p.process(flagsChanged(63, flags: [.maskSecondaryFn]))
        // User actually pressed Fn+K — Fn combos are unsupported; K alone has no modifier.
        _ = p.process(keyDown(40, flags: [.maskSecondaryFn]))
        let action = p.process(keyUp(40, flags: [.maskSecondaryFn]))

        guard case .emit(.shortcutCaptureRejected, _) = action else {
            Issue.record("Expected rejection, got \(action)")
            return
        }
    }

    @Test("bare Fn hotkey: hold and release drives hotkeyDown/hotkeyUp, passed through")
    func fnHoldToTalk() {
        var p = HotkeyEventProcessor(hotkey: Hotkey(keyCode: 63, modifiers: []))

        #expect(p.process(flagsChanged(63, flags: [.maskSecondaryFn])) == .emit(.hotkeyDown, swallow: false))
        #expect(p.isHotkeyHeld)
        #expect(p.process(flagsChanged(63, flags: [])) == .emit(.hotkeyUp, swallow: false))
        #expect(!p.isHotkeyHeld)
    }

    @Test("bare Fn hotkey: escape while held cancels")
    func fnEscapeCancels() {
        var p = HotkeyEventProcessor(hotkey: Hotkey(keyCode: 63, modifiers: []))
        _ = p.process(flagsChanged(63, flags: [.maskSecondaryFn]))

        #expect(p.process(keyDown(53)) == .emit(.escapePressed, swallow: true))
    }

    @Test("bare Fn hotkey: other keys pass through untouched")
    func fnHotkeyIgnoresOtherKeys() {
        var p = HotkeyEventProcessor(hotkey: Hotkey(keyCode: 63, modifiers: []))
        #expect(p.process(keyDown(49, flags: ctrlOpt)) == .pass)
        #expect(p.process(flagsChanged(59, flags: [.maskControl])) == .pass)
    }

    // MARK: - Settings validation (ADR-008)

    @Test("settings validation accepts bare Fn hotkey")
    func settingsAcceptBareFn() throws {
        var settings = UttrSettings.default
        settings.hotkey.keyCode = Hotkey.fnGlobeKeyCode
        settings.hotkey.modifiers = []
        try settings.validate()
    }

    @Test("settings validation still rejects other modifier-less hotkeys")
    func settingsRejectModifierless() {
        var settings = UttrSettings.default
        settings.hotkey.keyCode = 49
        settings.hotkey.modifiers = []
        #expect(throws: UttrSettings.ValidationError.hotkeyMissingModifier) {
            try settings.validate()
        }
    }

    @Test("Fn hotkey display string")
    func fnDisplayString() {
        #expect(Hotkey(keyCode: 63, modifiers: []).isFnGlobe)
        #expect(Hotkey(keyCode: 63, modifiers: []).displayString == "🌐 Globe (Fn)")
        #expect(!Hotkey.default.isFnGlobe)
    }
}
