import Foundation
import GRDB

/// Shared conformance for every GRDB record (ADR-0012). Dates are stored as REAL Unix seconds.
///
/// The two date strategies are declared as protocol requirements, matching GRDB's
/// `EncodableRecord` and `FetchableRecord` requirements, so GRDB dispatches to these defaults.
/// A plain extension method would be ignored by GRDB.
protocol StudyRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy
    static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy
}

extension StudyRecord {
    static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .timeIntervalSince1970
    }

    static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .timeIntervalSince1970
    }
}

extension Date {
    /// Rounded down to a multiple of 1/1024 s. Such dates survive the REAL Unix-seconds round trip exactly
    /// (ADR-0012), so a saved record is == to its fetched copy. Idempotent.
    var storageRounded: Date {
        Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate * 1024).rounded(.down) / 1024)
    }

    /// The value to bind wherever a date appears in SQL: `filter` expressions, `SQL` interpolation,
    /// `arguments:` and `updateAll` assignments (ADR-0012). It's the same `Double` the `StudyRecord`
    /// encoder writes for this date. Never bind a bare `Date`: GRDB binds it as TEXT, and in SQLite
    /// every REAL sorts before every TEXT, so `dueAt <= date` would match every row.
    /// Example: `ReviewCard.filter(Column("dueAt") <= now.databaseUnixSeconds)`.
    var databaseUnixSeconds: Double {
        timeIntervalSince1970
    }
}
