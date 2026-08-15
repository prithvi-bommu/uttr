import Foundation
@testable import Uttr

/// In-memory implementation of `BuildVersionStorage` for unit tests.
/// Avoids touching `UserDefaults.standard` so tests are isolated and
/// deterministic.
final class MockBuildVersionStorage: BuildVersionStorage, @unchecked Sendable {
    private var store: [String: String] = [:]

    func string(forKey key: String) -> String? {
        store[key]
    }

    func set(_ value: String?, forKey key: String) {
        store[key] = value
    }
}
