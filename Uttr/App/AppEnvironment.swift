import Foundation

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let appState = AppState()
    let configStore = ConfigurationStore()
    let permissionService: PermissionChecking = RealPermissionService()

    private init() {
        configStore.load()
    }
}
