import Foundation
import GRDB

// Column enums. Raw values equal the CHECK lists in ARCHITECTURE §4 exactly.

enum FileType: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case pdf, markdown
}

enum CoverSource: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case automatic = "default", custom, page
}

enum ExtractionStatus: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case pending, done, failed
}

enum HighlightKind: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case text, image
}

/// highlight.view
enum ReaderViewKind: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case pdf, text, markdown
}

enum AnchorStatus: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case ok, orphaned
}

/// category.frequency, reviewCard.frequencyOverride
enum ReviewFrequency: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case off, low, normal, high
}

enum CardType: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case passive, cloze, qa
}

/// reviewCard.state (copy of FSRS state)
enum CardState: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case new, learning, review, relearning
}

enum SuspendedReason: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case mastery, frequencyOff, user
}

enum ReviewSessionKind: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case daily, themed
}

enum ReviewOrderMode: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case dueFirst, random
}

enum ExportFormat: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case markdown, html
}

/// highlight.color 0–4 (SPEC F-06). Labels are UI/Settings (Phase 1), not here.
enum HighlightColor: Int, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case yellow = 0, green = 1, blue = 2, pink = 3, purple = 4
}
