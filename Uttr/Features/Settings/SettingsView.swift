import SwiftUI

struct SettingsView: View {
    @State private var store: ConfigurationStore
    private let appState: AppState
    private let permissionService: PermissionChecking
    private let onBeginCapture: () -> Void
    private let onCancelCapture: () -> Void

    init(
        store: ConfigurationStore,
        appState: AppState,
        permissionService: PermissionChecking,
        onBeginCapture: @escaping () -> Void,
        onCancelCapture: @escaping () -> Void
    ) {
        self._store = State(initialValue: store)
        self.appState = appState
        self.permissionService = permissionService
        self.onBeginCapture = onBeginCapture
        self.onCancelCapture = onCancelCapture
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

            TranscriptionSettingsView(store: store)
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
