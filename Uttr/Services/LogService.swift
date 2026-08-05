import Foundation
import OSLog

enum LogService {
    static let general = Logger(subsystem: "com.uttr.app", category: "general")
    static let audio = Logger(subsystem: "com.uttr.app", category: "audio")
    static let transcription = Logger(subsystem: "com.uttr.app", category: "transcription")
    static let hotkey = Logger(subsystem: "com.uttr.app", category: "hotkey")
    static let paste = Logger(subsystem: "com.uttr.app", category: "paste")
    static let polish = Logger(subsystem: "com.uttr.app", category: "polish")
    static let config = Logger(subsystem: "com.uttr.app", category: "config")
    static let permissions = Logger(subsystem: "com.uttr.app", category: "permissions")
}
