import Foundation
import OSLog

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let appState = AppState()
    let configStore = ConfigurationStore()
    let permissionService: PermissionChecking = RealPermissionService()
    let hotkeyService: HotkeyServiceProtocol = EventTapHotkeyService()
    let transcriptionCoordinator = TranscriptionCoordinator()
    private(set) var dictationController: DictationController!
    private let logger = Logger(subsystem: "com.uttr.app", category: "app")

    private init() {
        configStore.load()
        dictationController = DictationController(
            appState: appState,
            recorder: AVAudioEngineRecorder(),
            coordinator: transcriptionCoordinator,
            pasteService: PasteService()
        )
        configureTranscription()
        startHotkeyService()
    }

    /// (Re)applies engine/model selection. Called at launch and whenever the
    /// Transcription settings change. Preparation runs in the background and
    /// never blocks menu-bar launch (spec §8).
    func configureTranscription() {
        transcriptionCoordinator.configure(
            selection: configStore.settings.transcriptionEngine,
            whisperModel: configStore.settings.whisperModel
        )
    }

    func startHotkeyService() {
        let hotkey = Hotkey(
            keyCode: configStore.settings.hotkey.keyCode,
            modifiers: Set(configStore.settings.hotkey.modifiers)
        )

        hotkeyService.start(hotkey: hotkey) { [weak self] event in
            Task { @MainActor in
                self?.handleHotkeyEvent(event)
            }
        }
    }

    private func handleHotkeyEvent(_ event: HotkeyEvent) {
        switch event {
        case .hotkeyDown:
            let missingPermission = checkPermissions()
            if let blocker = missingPermission {
                appState.handle(.permissionBlocked(blocker))
                return
            }
            if appState.handle(.hotkeyDown) {
                dictationController.recordingStarted()
            }

        case .hotkeyUp:
            if appState.handle(.hotkeyUp) {
                dictationController.recordingEnded()
            }

        case .escapePressed:
            if appState.handle(.escapePressed) {
                dictationController.recordingCancelled()
            }

        case .shortcutCaptured(let keyCode, let modifiers):
            try? configStore.update {
                $0.hotkey.keyCode = keyCode
                $0.hotkey.modifiers = Array(modifiers)
            }
            hotkeyService.updateHotkey(Hotkey(keyCode: keyCode, modifiers: modifiers))
            appState.handle(.hotkeyCaptureDone)
            logger.info("Hotkey rebound to keyCode \(keyCode)")

        case .shortcutCaptureRejected:
            appState.handle(.cancelHotkeyCapture)
        }
    }

    func checkPermissions() -> PermissionBlocker? {
        if permissionService.microphoneStatus() == .notGranted {
            return .microphone
        }
        if permissionService.accessibilityStatus() == .notGranted {
            return .accessibility
        }
        return nil
    }

    func beginShortcutCapture() {
        appState.handle(.beginHotkeyCapture)
        hotkeyService.beginCapture()
    }

    func cancelShortcutCapture() {
        hotkeyService.cancelCapture()
        appState.handle(.cancelHotkeyCapture)
    }
}
