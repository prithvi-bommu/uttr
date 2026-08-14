import CoreGraphics
import Foundation
import Testing
@testable import Uttr

@Suite("macOS Compatibility")
struct MacOSCompatibilityTests {

    // MARK: - Deployment target baseline

    @Test("deployment target is macOS 15.0+")
    func deploymentTarget() {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #expect(version.majorVersion >= 15,
                "Uttr requires macOS 15.0+; running on \(version.majorVersion).\(version.minorVersion)")
    }

    // MARK: - Transcription engine selection across OS versions

    @Test("automatic selection falls back to WhisperKit on macOS 15 (no System Speech)")
    @MainActor func automaticOnSequoia() {
        let coordinator = TranscriptionCoordinator(
            factory: MockEngineFactory(),
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: false)
        )
        #expect(coordinator.resolveEngineID(selection: .automatic) == .whisperKit)
    }

    @Test("automatic selection uses System Speech on macOS 26+ when available")
    @MainActor func automaticOnTahoe() {
        let systemEngine = MockTranscriptionEngine(id: .systemSpeech)
        let coordinator = TranscriptionCoordinator(
            factory: MockEngineFactory(systemEngine: systemEngine),
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: true)
        )
        #expect(coordinator.resolveEngineID(selection: .automatic) == .systemSpeech)
    }

    @Test("systemSpeech selection degrades gracefully when System Speech unavailable")
    @MainActor func systemSpeechDegradation() {
        let coordinator = TranscriptionCoordinator(
            factory: MockEngineFactory(systemEngine: nil),
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: false)
        )
        #expect(coordinator.resolveEngineID(selection: .systemSpeech) == .whisperKit)
    }

    @Test("availability reports true but factory has no engine yet — still falls back")
    @MainActor func availabilityWithoutFactoryEngine() {
        let coordinator = TranscriptionCoordinator(
            factory: MockEngineFactory(systemEngine: nil),
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: true)
        )
        #expect(coordinator.resolveEngineID(selection: .automatic) == .whisperKit)
    }

    @Test("whisperKit selection always resolves to WhisperKit regardless of OS")
    @MainActor func whisperKitAlwaysWins() {
        let systemEngine = MockTranscriptionEngine(id: .systemSpeech)
        let coordinator = TranscriptionCoordinator(
            factory: MockEngineFactory(systemEngine: systemEngine),
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: true)
        )
        #expect(coordinator.resolveEngineID(selection: .whisperKit) == .whisperKit)
    }

    // MARK: - Permission API compatibility

    @Test("permission status enum covers all three states")
    func permissionStatusCoverage() {
        let allStatuses: [PermissionStatus] = [.granted, .notGranted, .unknown]
        #expect(Set(allStatuses).count == 3)
    }

    @Test("permission service returns consistent statuses")
    func permissionServiceMock() {
        let mock = MockPermissionService()

        mock.micStatus = .granted
        mock.inputStatus = .granted
        mock.accessStatus = .granted
        #expect(mock.microphoneStatus() == .granted)
        #expect(mock.inputMonitoringStatus() == .granted)
        #expect(mock.accessibilityStatus() == .granted)

        mock.micStatus = .unknown
        mock.inputStatus = .unknown
        mock.accessStatus = .unknown
        #expect(mock.microphoneStatus() == .unknown)
        #expect(mock.inputMonitoringStatus() == .unknown)
        #expect(mock.accessibilityStatus() == .unknown)
    }

    @Test("all three permission blockers are distinct and named")
    func permissionBlockerCompleteness() {
        let blockers: [PermissionBlocker] = [.microphone, .inputMonitoring, .accessibility]
        let names = blockers.map(\.statusText)
        #expect(Set(names).count == 3, "Each blocker must have a unique status text")
        for name in names {
            #expect(!name.isEmpty)
        }
    }

    // MARK: - System Settings URL format (stable across macOS 15–26+)

    @Test("system settings URLs use x-apple.systempreferences scheme")
    func settingsURLScheme() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
        ]
        for string in urls {
            let url = URL(string: string)
            #expect(url != nil, "URL '\(string)' must be parseable")
            #expect(url?.scheme == "x-apple.systempreferences")
        }
    }

    // MARK: - Fn/Globe key compatibility

    @Test("FnGlobeAction covers all documented AppleFnUsageType values")
    func fnGlobeActionCoverage() {
        let actions: [FnGlobeAction] = [
            .doNothing, .changeInputSource, .showEmojiAndSymbols, .startDictation, .unknown,
        ]
        #expect(actions.count == 5)
        let displayNames = actions.map(\.displayName)
        #expect(Set(displayNames).count == 5, "Each action has a unique display name")
    }

    @Test("bare Fn hotkey down/up cycle works")
    func bareFnHoldToTalk() {
        var processor = HotkeyEventProcessor(
            hotkey: Hotkey(keyCode: Hotkey.fnGlobeKeyCode, modifiers: [])
        )

        let down = processor.process(KeyEventInput(
            kind: .flagsChanged,
            keyCode: Hotkey.fnGlobeKeyCode,
            flags: .maskSecondaryFn
        ))
        #expect(down == .emit(.hotkeyDown, swallow: false))
        #expect(processor.isHotkeyHeld)

        let up = processor.process(KeyEventInput(
            kind: .flagsChanged,
            keyCode: Hotkey.fnGlobeKeyCode,
            flags: []
        ))
        #expect(up == .emit(.hotkeyUp, swallow: false))
        #expect(!processor.isHotkeyHeld)
    }

    // MARK: - Hotkey event processing (OS-agnostic robustness)

    @Test("modifier release during hold-to-talk emits hotkeyUp (not stuck held)")
    func modifierReleaseUnsticks() {
        let hotkey = Hotkey(keyCode: 49, modifiers: [.control, .option])
        var processor = HotkeyEventProcessor(hotkey: hotkey)

        let down = processor.process(KeyEventInput(
            kind: .keyDown, keyCode: 49,
            flags: [.maskControl, .maskAlternate]
        ))
        #expect(down == .emit(.hotkeyDown, swallow: true))

        let modRelease = processor.process(KeyEventInput(
            kind: .flagsChanged, keyCode: 49,
            flags: .maskControl // Option released
        ))
        #expect(modRelease == .emit(.hotkeyUp, swallow: false))
        #expect(!processor.isHotkeyHeld)
    }

    @Test("escape during active hold cancels dictation")
    func escapeWhileHeld() {
        let hotkey = Hotkey(keyCode: 49, modifiers: [.control, .option])
        var processor = HotkeyEventProcessor(hotkey: hotkey)

        _ = processor.process(KeyEventInput(
            kind: .keyDown, keyCode: 49,
            flags: [.maskControl, .maskAlternate]
        ))
        #expect(processor.isHotkeyHeld)

        let esc = processor.process(KeyEventInput(
            kind: .keyDown, keyCode: HotkeyEventProcessor.escapeKeyCode,
            flags: [.maskControl, .maskAlternate]
        ))
        #expect(esc == .emit(.escapePressed, swallow: true))
        #expect(!processor.isHotkeyHeld)
    }

    @Test("reserved system shortcuts are rejected during capture")
    func reservedShortcutRejection() {
        var processor = HotkeyEventProcessor(
            hotkey: Hotkey(keyCode: 49, modifiers: [.control, .option])
        )
        processor.beginCapture()

        // Cmd-Space (Spotlight)
        _ = processor.process(KeyEventInput(
            kind: .keyDown, keyCode: 49,
            flags: .maskCommand
        ))
        let result = processor.process(KeyEventInput(
            kind: .keyUp, keyCode: 49,
            flags: .maskCommand
        ))
        if case .emit(.shortcutCaptureRejected(let reason), _) = result {
            #expect(reason.contains("reserved"))
        } else {
            Issue.record("Expected shortcutCaptureRejected for Cmd-Space")
        }
    }

    @Test("shortcut capture rejects bare key without modifiers")
    func bareKeyCaptureRejected() {
        var processor = HotkeyEventProcessor(
            hotkey: Hotkey(keyCode: 49, modifiers: [.control, .option])
        )
        processor.beginCapture()

        _ = processor.process(KeyEventInput(kind: .keyDown, keyCode: 0, flags: []))
        let result = processor.process(KeyEventInput(kind: .keyUp, keyCode: 0, flags: []))
        if case .emit(.shortcutCaptureRejected(let reason), _) = result {
            #expect(reason.contains("modifier"))
        } else {
            Issue.record("Expected rejection for bare key capture")
        }
    }

    // MARK: - Recording indicator sizing (macOS 26 constraint-loop fix)

    @Test("indicator window size is fixed and nonzero")
    func indicatorWindowSize() {
        let size = RecordingIndicatorView.windowSize
        #expect(size.width > 0)
        #expect(size.height > 0)
        #expect(size.width == 230)
        #expect(size.height == 44)
    }

    // MARK: - State machine robustness across OS versions

    @Test("full dictation cycle completes: idle -> recording -> transcribing -> polishing -> pasting -> idle")
    @MainActor func fullDictationCycle() {
        let state = AppState()
        #expect(state.dictationState.isIdle)

        state.handle(.hotkeyDown)
        #expect(state.dictationState.isRecording)

        state.handle(.hotkeyUp)
        #expect(state.dictationState == .transcribing)

        state.handle(.transcriptionCompleted("test"))
        #expect(state.dictationState == .polishing)

        state.handle(.polishCompleted("Test."))
        #expect(state.dictationState == .pasting)

        state.handle(.pasteCompleted)
        #expect(state.dictationState.isIdle)
    }

    @Test("permission block/resolve cycle works from idle")
    @MainActor func permissionBlockCycle() {
        let state = AppState()
        for blocker in [PermissionBlocker.microphone, .inputMonitoring, .accessibility] {
            state.handle(.permissionBlocked(blocker))
            #expect(state.dictationState == .blocked(blocker))
            state.handle(.permissionResolved)
            #expect(state.dictationState.isIdle)
        }
    }

    // MARK: - Login item service protocol compatibility (SMAppService, macOS 13+)

    @Test("login item protocol methods exist and compile")
    func loginItemProtocol() {
        struct StubLoginItem: LoginItemManaging {
            var isEnabled: Bool { false }
            func setEnabled(_ enabled: Bool) throws {}
        }
        let stub = StubLoginItem()
        #expect(!stub.isEnabled)
    }

    // MARK: - UserDefaults suite for Fn usage (stable across macOS versions)

    @Test("HIToolbox defaults suite is accessible")
    func hiToolboxSuiteAccessible() {
        let defaults = UserDefaults(suiteName: "com.apple.HIToolbox")
        #expect(defaults != nil, "com.apple.HIToolbox suite should be readable")
    }

    // MARK: - Window identifier matching (SwiftUI scene IDs across OS versions)

    @Test("window identifier matching handles SwiftUI scene format variations")
    @MainActor func windowIdentifierVariations() {
        #expect(WindowFocus.identifierMatches("onboarding-AppWindow-1", marker: "onboarding"))
        #expect(WindowFocus.identifierMatches("com_apple_SwiftUI_Settings_window", marker: "settings"))
        #expect(WindowFocus.identifierMatches("Diagnostics-AppWindow-1", marker: "diagnostics"))
        // Future format: scene IDs might change casing or separators
        #expect(WindowFocus.identifierMatches("ONBOARDING-Window-2", marker: "onboarding"))
        #expect(WindowFocus.identifierMatches("settings-panel-main", marker: "settings"))
        #expect(!WindowFocus.identifierMatches(nil, marker: "settings"))
        #expect(!WindowFocus.identifierMatches("", marker: "settings"))
    }

    // MARK: - Audio capture data structure

    @Test("CapturedAudio can represent various sample rates")
    func capturedAudioSampleRates() {
        let rates: [Double] = [16_000, 44_100, 48_000]
        for rate in rates {
            let audio = CapturedAudio(samples: [0.1, 0.2, 0.3], sampleRate: rate)
            #expect(audio.sampleRate == rate)
            #expect(audio.samples.count == 3)
        }
    }

    @Test("CapturedAudio handles empty samples")
    func capturedAudioEmpty() {
        let audio = CapturedAudio(samples: [], sampleRate: 16_000)
        #expect(audio.samples.isEmpty)
    }
}
