import SwiftUI

struct SettingsView: View {
    @State private var store: ConfigurationStore
    private let permissionService: PermissionChecking

    init(store: ConfigurationStore, permissionService: PermissionChecking = RealPermissionService()) {
        self._store = State(initialValue: store)
        self.permissionService = permissionService
    }

    var body: some View {
        TabView {
            GeneralSettingsView(store: store)
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
