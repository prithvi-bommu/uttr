import SwiftUI

struct SettingsView: View {
    @State private var store: ConfigurationStore
    private let appState: AppState
    private let permissionService: PermissionChecking
    private let paymentGateway: any PaymentGateway
    private let onBeginCapture: () -> Void
    private let onCancelCapture: () -> Void
    private let transcriptionCoordinator: TranscriptionCoordinator?
    private let onTranscriptionChanged: (() -> Void)?
    private let onStartAtLoginChanged: ((Bool) -> Bool)?
    private let onAIConfigChanged: (() -> Void)?
    private let updater: UpdaterServicing?

    init(
        store: ConfigurationStore,
        appState: AppState,
        permissionService: PermissionChecking,
        paymentGateway: any PaymentGateway,
        onBeginCapture: @escaping () -> Void,
        onCancelCapture: @escaping () -> Void,
        transcriptionCoordinator: TranscriptionCoordinator? = nil,
        onTranscriptionChanged: (() -> Void)? = nil,
        onStartAtLoginChanged: ((Bool) -> Bool)? = nil,
        onAIConfigChanged: (() -> Void)? = nil,
        updater: UpdaterServicing? = nil
    ) {
        self._store = State(initialValue: store)
        self.appState = appState
        self.permissionService = permissionService
        self.paymentGateway = paymentGateway
        self.onBeginCapture = onBeginCapture
        self.onCancelCapture = onCancelCapture
        self.transcriptionCoordinator = transcriptionCoordinator
        self.onTranscriptionChanged = onTranscriptionChanged
        self.onStartAtLoginChanged = onStartAtLoginChanged
        self.onAIConfigChanged = onAIConfigChanged
        self.updater = updater
    }

    var body: some View {
        TabView {
            GeneralSettingsView(
                store: store,
                appState: appState,
                onBeginCapture: onBeginCapture,
                onCancelCapture: onCancelCapture,
                onStartAtLoginChanged: onStartAtLoginChanged,
                updater: updater
            )
            .tabItem { Label("General", systemImage: "gear") }

            TranscriptionSettingsView(
                store: store,
                coordinator: transcriptionCoordinator,
                onSelectionChanged: onTranscriptionChanged
            )
            .tabItem { Label("Transcription", systemImage: "waveform") }

            PolishSettingsView(store: store, paymentGateway: paymentGateway)
                .tabItem { Label("Text Polish", systemImage: "sparkles") }

            AIContentSettingsView(store: store, paymentGateway: paymentGateway, onConfigChanged: onAIConfigChanged)
                .tabItem { Label("AI Content", systemImage: "wand.and.stars") }

            PermissionsSettingsView(permissionService: permissionService)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }

            PrivacySettingsView()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }

            SubscriptionSettingsView(paymentGateway: paymentGateway)
                .tabItem { Label("Subscription", systemImage: "creditcard") }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
