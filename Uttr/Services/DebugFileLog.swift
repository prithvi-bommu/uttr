import Foundation

/// DEBUG-build-only file logger for agent-assisted diagnosis.
///
/// The development agent's sandbox cannot read the unified system log
/// (`log show` → "Cannot run while sandboxed"), so during development the
/// highest-signal operational events are mirrored to a plain file it can
/// read directly:
///
///     ~/Library/Application Support/Uttr/debug.log
///
/// Privacy contract (spec §11) still applies in full: state transitions,
/// error categories, and counts only — never transcript text, audio,
/// clipboard contents, or API keys. Compiled out of Release builds entirely.
enum DebugFileLog {
    #if DEBUG
    private static let lock = NSLock()
    private static let maxBytes = 512 * 1024

    private static let fileURL: URL = {
        let dir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("Uttr", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return dir.appendingPathComponent("debug.log")
    }()

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
    #endif

    /// Appends one redacted operational line. No-op in Release builds.
    static func append(_ category: String, _ message: String) {
        #if DEBUG
        lock.withLock {
            let line = "\(timestamp.string(from: Date())) [\(category)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            let path = fileURL.path
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(
                    atPath: path, contents: nil,
                    attributes: [.posixPermissions: 0o600]
                )
            }
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            defer { try? handle.close() }

            // Simple size cap: truncate the file when it grows past the limit.
            if let size = try? handle.seekToEnd(), size > UInt64(maxBytes) {
                try? handle.truncate(atOffset: 0)
            }
            try? handle.write(contentsOf: data)
        }
        #endif
    }
}
