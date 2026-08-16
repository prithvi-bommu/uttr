import Foundation
import OSLog

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let appState = AppState()
    let configStore = ConfigurationStore()
    let permissionService: PermissionChecking = RealPermissionService()
    let hotkeyService: HotkeyServiceProtocol = EventTapHotkeyService()
    let loginItemService: LoginItemManaging = SMAppServiceLoginItem()
    let updaterService: UpdaterServicing = SparkleUpdaterService()
    let transcriptionCoordinator = TranscriptionCoordinator()
    let dictationMetrics = DictationMetrics()
    let paymentGateway: any PaymentGateway
    private let recorder = AVAudioEngineRecorder()
    private(set) var recordingIndicator: RecordingIndicatorController!
    private(set) var dictationController: DictationController!
    private let logger = Logger(subsystem: "com.uttr.app", category: "app")

    private init() {
        let gateway = RevenueCatGateway(pricingConfig: PricingConfigLoader.load())
        self.paymentGateway = gateway
        Task { await gateway.configure() }

        configStore.load()
        recordingIndicator = RecordingIndicatorController(recorder: recorder)
        dictationController = DictationController(
            appState: appState,
            recorder: recorder,
            coordinator: transcriptionCoordinator,
            pasteService: PasteService(),
            metrics: dictationMetrics,
            localPolisherProvider: { [configStore] in
                let config = configStore.settings.localPolish
                guard config.enabled else { return nil }
                return RuleBasedTextPolisher(options: .init(config: config))
            },
            cloudPolisherProvider: { [configStore, gateway] in
                guard gateway.subscriptionStatus.hasPremiumAccess else { return nil }
                return TextPolisherFactory.make(config: configStore.settings.cloudPolish)
            },
            aiProvider: { [configStore, gateway] in
                guard gateway.subscriptionStatus.hasPremiumAccess else { return nil }
                let config = configStore.settings.aiContent
                guard config.enabled else { return nil }
                return AIContentProviderFactory.make(config: config)
            },
            polishCoordinatorProvider: { [configStore] in
                PolishCoordinator(budgetMs: configStore.settings.cloudPolish.polishBudgetMs)
            }
        )
        configureTranscription()
        startHotkeyService()
        reconcileLoginItem()
        appState.onStateChange = { [weak self] state in
            self?.recordingIndicator.stateChanged(state)
        }
    }

    /// Applies the user's start-at-login choice to the system and persists it.
    /// Returns false when the system refused the change (setting is not saved
    /// so the toggle snaps back to reality).
    @discardableResult
    func applyStartAtLogin(_ enabled: Bool) -> Bool {
        do {
            try loginItemService.setEnabled(enabled)
        } catch {
            logger.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        try? configStore.update { $0.startAtLogin = enabled }
        return true
    }

    /// At launch, bring the system registration in line with the stored
    /// setting. Registration can drift: rebuilds/moves can drop it, or the
    /// user may have removed the login item in System Settings.
    private func reconcileLoginItem() {
        let wanted = configStore.settings.startAtLogin
        guard loginItemService.isEnabled != wanted else { return }
        do {
            try loginItemService.setEnabled(wanted)
            logger.info("Reconciled login item to \(wanted, privacy: .public)")
        } catch {
            logger.error("Login item reconcile failed: \(error.localizedDescription, privacy: .public)")
        }
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
        applyAIHotkey()

        // The tap installs asynchronously and fails silently when Input
        // Monitoring is missing (every rebuild invalidates the grant,
        // ADR-006). Surface it in the menu bar instead of a dead hotkey.
        // The grant only applies after relaunch, so the blocked status is
        // accurate for this process's entire lifetime.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }
            if self.permissionService.inputMonitoringStatus() == .notGranted {
                self.appState.handle(.permissionBlocked(.inputMonitoring))
                self.logger.error("Input Monitoring not granted — hotkey inactive until granted + relaunch")
                DebugFileLog.append("app", "BLOCKED: Input Monitoring not granted — grant it and relaunch Uttr")
            }
        }
    }

    private func startRecording(mode: DictationMode) {
        if let blocker = checkPermissions() {
            appState.handle(.permissionBlocked(blocker))
            return
        }
        if appState.handle(.hotkeyDown) {
            dictationController.recordingStarted(mode: mode)
        }
    }

    private func handleHotkeyEvent(_ event: HotkeyEvent) {
        switch event {
        case .hotkeyDown:
            startRecording(mode: .dictation)

        case .aiHotkeyDown:
            guard paymentGateway.subscriptionStatus.hasPremiumAccess else { return }
            guard configStore.settings.aiContent.enabled else { return }
            startRecording(mode: .aiContent)

        case .hotkeyUp, .aiHotkeyUp:
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

    /// Registers or clears the AI-content hotkey from current settings.
    /// Called at startup and whenever the AI Content settings change.
    func applyAIHotkey() {
        let config = configStore.settings.aiContent
        guard config.enabled else {
            hotkeyService.updateAIHotkey(nil)
            return
        }
        hotkeyService.updateAIHotkey(Hotkey(
            keyCode: config.hotkey.keyCode,
            modifiers: Set(config.hotkey.modifiers)
        ))
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
