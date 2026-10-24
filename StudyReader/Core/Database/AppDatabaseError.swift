import Foundation
import GRDB

/// Failures opening the library database (ARCHITECTURE §14). Messages never contain SQL, paths or user data.
enum AppDatabaseError: Error, Equatable, LocalizedError {
    /// The library folder couldn't be created.
    case folderUnavailable
    /// SQLite couldn't open the file. `code` is the SQLite primary result code (-1 if not a SQLite error); for logs only.
    case cannotOpen(code: Int32)
    /// The file is not a database or is corrupt (SQLITE_NOTADB, SQLITE_CORRUPT).
    case damaged(code: Int32)
    /// A migration failed for another reason. `code` as above.
    case migrationFailed(code: Int32)
    /// The library was migrated by a newer StudyReader build (unknown migration identifiers).
    case newerVersion
    /// SQLITE_FULL or SQLITE_IOERR at open or migration.
    case storageFailure(code: Int32)
    /// SQLITE_BUSY or SQLITE_LOCKED at open or migration.
    case busy(code: Int32)

    enum Stage: String, Sendable { case open, migrate }

    /// AppDatabaseError → returned unchanged.
    /// Any error that isn't a DatabaseError → .cannotOpen(code: -1) for .open, .migrationFailed(code: -1) for .migrate.
    /// DatabaseError with primary resultCode .SQLITE_NOTADB or .SQLITE_CORRUPT → .damaged(code:).
    /// DatabaseError with primary resultCode .SQLITE_FULL or .SQLITE_IOERR → .storageFailure(code:).
    /// DatabaseError with primary resultCode .SQLITE_BUSY or .SQLITE_LOCKED → .busy(code:).
    /// Other DatabaseError → .cannotOpen(code:) for .open, .migrationFailed(code:) for .migrate.
    static func wrap(_ error: any Error, stage: Stage) -> AppDatabaseError {
        if let appError = error as? AppDatabaseError {
            return appError
        }
        guard let databaseError = error as? DatabaseError else {
            return failure(code: -1, stage: stage)
        }
        let primary = databaseError.resultCode.primaryResultCode
        let code = primary.rawValue
        if primary == .SQLITE_NOTADB || primary == .SQLITE_CORRUPT {
            return .damaged(code: code)
        }
        if primary == .SQLITE_FULL || primary == .SQLITE_IOERR {
            return .storageFailure(code: code)
        }
        if primary == .SQLITE_BUSY || primary == .SQLITE_LOCKED {
            return .busy(code: code)
        }
        return failure(code: code, stage: stage)
    }

    var errorDescription: String? {
        switch self {
        case .folderUnavailable:
            String(localized: "StudyReader couldn't create its library folder.")
        case .cannotOpen:
            String(localized: "StudyReader couldn't open its library.")
        case .damaged:
            String(localized: "The library database is damaged.")
        case .migrationFailed:
            String(localized: "StudyReader couldn't update its library to this version.")
        case .newerVersion:
            String(localized: "This library was updated by a newer version of StudyReader.")
        case .storageFailure:
            String(localized: "StudyReader couldn't write to its library.")
        case .busy:
            String(localized: "The library is in use by another copy of StudyReader.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .folderUnavailable, .cannotOpen:
            String(localized: "Check that your Mac has free disk space, then reopen StudyReader.")
        case .damaged:
            String(localized: "Restore the StudyReader folder from a backup, then reopen StudyReader.")
        case .migrationFailed:
            String(localized: "Quit and reopen StudyReader. If this keeps happening, back up the StudyReader folder before trying anything else.")
        case .newerVersion:
            String(localized: "Open it with the newer version of StudyReader.")
        case .storageFailure:
            String(localized: "Check that your Mac has free disk space, then reopen StudyReader.")
        case .busy:
            String(localized: "Quit other copies of StudyReader, then reopen it.")
        }
    }

    private static func failure(code: Int32, stage: Stage) -> AppDatabaseError {
        switch stage {
        case .open: .cannotOpen(code: code)
        case .migrate: .migrationFailed(code: code)
        }
    }
}
