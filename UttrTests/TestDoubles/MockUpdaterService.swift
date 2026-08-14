import Foundation
@testable import Uttr

@MainActor
final class MockUpdaterService: UpdaterServicing {
    var automaticallyChecksForUpdates: Bool = false
    var canCheckForUpdates: Bool = true
    var lastUpdateCheckDate: Date?
    var checkForUpdatesCalled = false

    func checkForUpdates() {
        checkForUpdatesCalled = true
    }
}
