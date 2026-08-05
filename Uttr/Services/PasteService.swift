import Foundation
import OSLog

/// Delivery of final text into the focused app. The real implementation
/// (pasteboard write + synthetic Command-V + race-safe restore) is M4 scope.
/// M3 ships this protocol plus a logging placeholder so the full dictation
/// pipeline is exercised end-to-end against a paste seam.
protocol PasteServicing: Sendable {
    /// Delivers `text` to the focused application.
    /// - Returns: true when delivery is believed successful.
    func paste(_ text: String) async -> Bool
}

/// M3 placeholder: records that text reached the paste stage without touching
/// the pasteboard or posting events. Replaced by the real PasteService in M4.
/// Deliberately does NOT log transcript contents (privacy contract §11).
struct PlaceholderPasteService: PasteServicing {
    private let logger = Logger(subsystem: "com.uttr.app", category: "paste")

    func paste(_ text: String) async -> Bool {
        logger.info("Paste stage reached (\(text.count, privacy: .public) characters) — real paste lands in M4")
        return true
    }
}
