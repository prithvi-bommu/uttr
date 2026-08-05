import Foundation

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let appState = AppState()

    private init() {}
}
