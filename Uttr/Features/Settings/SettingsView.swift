import SwiftUI

struct SettingsView: View {
    @State private var store: ConfigurationStore
    private let appState: AppState
    private let permissionService: PermissionChecking
    private let onBeginCapture: () -> Void
    private let onCancelCapture: () -> Void
    private let transcriptionCoordinator: TranscriptionCoordinator?
    private let onTranscriptionChanged: (() -> Void)?

    init(
        store: ConfigurationStore,
        appState: AppState,
        permissionService: PermissionChecking,
        onBeginCapture: @escaping () -> Void,
        onCancelCapture: @escaping () -> Void,
        transcriptionCoordinator: TranscriptionCoordinator? = nil,
        onTranscriptionChanged: (() -> Void)? = nil
    ) {
        self._store = State(initialValue: store)
        self.appState = appState
        self.permissionService = permissionService
        self.onBeginCapture = onBeginCapture
        self.onCancelCapture = onCancelCapture
        self.transcriptionCoordinator = transcriptionCoordinator
        self.onTranscriptionChanged = onTranscriptionChanged
    }

    var body: some View {
        TabView {
            GeneralSettingsView(
                store: store,
                appState: appState,
                onBeginCapture: onBeginCapture,
                onCancelCapture: onCancelCapture
            )
            .tabItem { Label("General", systemImage: "gear") }

            TranscriptionSettingsView(
                store: store,
                coordinator: transcriptionCoordinator,
                onSelectionChanged: onTranscriptionChanged
            )
            .tabItem { Label("Transcription", systemImage: "waveform") }

            PolishSettingsView(store: store)
                .tabItem { Label("Text Polish", systemImage: "sparkles") }

            PermissionsSettingsView(permissionService: permissionService)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }

            PrivacySettingsView()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
