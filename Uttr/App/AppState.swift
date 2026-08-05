import Foundation

@MainActor
@Observable
final class AppState {
    var dictationState: DictationState = .idle
}
