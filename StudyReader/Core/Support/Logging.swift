import os
import Foundation

/// Category loggers (ARCHITECTURE §14).
/// Never log highlight text, notes, file contents, tokens, or emails.
enum Log {
    static let subsystem: String = Bundle.main.bundleIdentifier ?? "com.ryanvafaei.StudyReader"

    static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    static let app = logger("app")
    static let database = logger("database")
    static let files = logger("files")
}
