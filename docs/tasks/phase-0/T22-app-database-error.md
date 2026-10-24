# T22: Typed `AppDatabaseError` for opening the library

- **Phase:** 0 (fix from bug hunt `docs/bugs/phase-0.md` L3, data part)
- **Agent:** data-layer
- **Depends on:** T19
- **ADRs:** none new; ARCHITECTURE §14 (typed errors, `LocalizedError`, no PII in logs)
- **Visual check needed:** no

## Goal
If the library can't be opened or migrated, the launch screen today shows GRDB's raw `description`. That text can include `while executing \`CREATE TABLE …\``. `AppDatabase.makeShared` should throw a typed `AppDatabaseError` with short user-facing messages, and log only the stage and the SQLite result code. T23 shows these messages in the UI.

## Files to touch
- `StudyReader/Core/Database/AppDatabaseError.swift` (new)
- `StudyReader/Core/Database/AppDatabase.swift` (modify `makeShared` only)
- `StudyReaderTests/CoreTests/AppDatabaseErrorTests.swift` (new)

## Interfaces to produce
```swift
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

    enum Stage: String, Sendable { case open, migrate }

    /// AppDatabaseError → returned unchanged.
    /// DatabaseError with primary resultCode .SQLITE_NOTADB or .SQLITE_CORRUPT → .damaged(code:).
    /// Other DatabaseError → .cannotOpen(code:) for .open, .migrationFailed(code:) for .migrate.
    /// Any other error → the same with code -1.
    static func wrap(_ error: any Error, stage: Stage) -> AppDatabaseError

    var errorDescription: String? { get }
    var recoverySuggestion: String? { get }
}
```
Messages: use `String(localized:)`. If the build adds them to `Localizable.xcstrings`, keep that change.

| Case | `errorDescription` | `recoverySuggestion` |
|---|---|---|
| `folderUnavailable` | "StudyReader couldn't create its library folder." | "Check that your Mac has free disk space, then reopen StudyReader." |
| `cannotOpen` | "StudyReader couldn't open its library." | "Check that your Mac has free disk space, then reopen StudyReader." |
| `damaged` | "The library database is damaged." | "Restore the StudyReader folder from a backup, then reopen StudyReader." |
| `migrationFailed` | "StudyReader couldn't update its library to this version." | "Quit and reopen StudyReader. If this keeps happening, back up the StudyReader folder before trying anything else." |

`makeShared(fileStore:)` becomes:
```swift
static func makeShared(fileStore: FileStore) throws -> AppDatabase {
    do {
        try fileStore.createRootDirectories()
    } catch {
        Log.database.error("Library folder unavailable")
        throw AppDatabaseError.folderUnavailable
    }
    let pool: DatabasePool
    do {
        pool = try DatabasePool(path: fileStore.databaseURL.path(percentEncoded: false), configuration: makeConfiguration())
    } catch {
        throw logged(AppDatabaseError.wrap(error, stage: .open), stage: .open)
    }
    do {
        return try AppDatabase(pool)
    } catch {
        throw logged(AppDatabaseError.wrap(error, stage: .migrate), stage: .migrate)
    }
}
```
`private static func logged(_ error: AppDatabaseError, stage: AppDatabaseError.Stage) -> AppDatabaseError` logs
`Log.database.error("Library open failed: stage=\(stage.rawValue, privacy: .public) case=\(String(describing: error), privacy: .public)")` and returns `error`. `String(describing:)` of this enum shows only the case and the code. Never log `localizedDescription`, the path, or the underlying `DatabaseError`.

Leave `init(_:)`, `makeInMemory()`, `makeConfiguration()` and `migrator` unchanged.

## Tests (`@Suite struct AppDatabaseErrorTests`; every store uses `defer { TestFileStore.remove(store) }`)
- `wrapMapsResultCodes`:
  - `wrap(DatabaseError(resultCode: .SQLITE_NOTADB), stage: .open) == .damaged(code: 26)`;
  - `wrap(DatabaseError(resultCode: .SQLITE_CORRUPT), stage: .migrate) == .damaged(code: 11)`;
  - `wrap(DatabaseError(resultCode: .SQLITE_CANTOPEN), stage: .open) == .cannotOpen(code: 14)`;
  - `wrap(DatabaseError(resultCode: .SQLITE_ERROR), stage: .migrate) == .migrationFailed(code: 1)`;
  - `wrap(CocoaError(.fileWriteNoPermission), stage: .open) == .cannotOpen(code: -1)`;
  - `wrap(AppDatabaseError.folderUnavailable, stage: .migrate) == .folderUnavailable`.
- `damagedFileIsReported`: `createRootDirectories()`, then write 1,024 bytes of `"not a database "` repeated to `store.databaseURL`. `makeShared(fileStore:)` throws an `AppDatabaseError` matching `case .damaged`. Use `#expect(throws: AppDatabaseError.self)`, then pattern-match with `if case .damaged = error {} else { Issue.record(…) }`.
- `migrationFailureIsReported`: create a database at `store.databaseURL` with a plain `DatabaseQueue(path:)`. Run `CREATE TABLE category (x)` and close it. `makeShared` throws `.migrationFailed(code: 1)`, because v1 hits "table category already exists".
- `folderFailureIsReported`: write a regular file `blocker` inside a fresh `temporaryDirectory/StudyReaderTests/<UUID>/` folder. Use `FileStore(rootURL: <that folder>/blocker/StudyReader)`. `makeShared` throws `.folderUnavailable`. Remove `<UUID>/` in a `defer`.
- `messagesNeverContainSQL`: for `[.folderUnavailable, .cannotOpen(code: 14), .damaged(code: 26), .migrationFailed(code: 1)]`:
  - `errorDescription` and `recoverySuggestion` are non-empty;
  - neither contains `"SQL"`, `"CREATE"`, `"while executing"`, `"/"` or a digit;
  - `error.localizedDescription == error.errorDescription`.
- `healthyLibraryStillOpens`: `makeShared` on a fresh store succeeds, and `appliedMigrations == ["v1", "v2"]`.

## Acceptance criteria
1. SQLite and other errors map to the four cases as specified. → test `AppDatabaseErrorTests/wrapMapsResultCodes`
2. A non-database file reports `.damaged`. → test `AppDatabaseErrorTests/damagedFileIsReported`
3. A failing migration reports `.migrationFailed`. → test `AppDatabaseErrorTests/migrationFailureIsReported`
4. A folder that can't be created reports `.folderUnavailable`. → test `AppDatabaseErrorTests/folderFailureIsReported`
5. User-facing texts contain no SQL, paths or codes. → test `AppDatabaseErrorTests/messagesNeverContainSQL`
6. The normal open path is unchanged. → tests `AppDatabaseErrorTests/healthyLibraryStillOpens`, `DatabaseMigrationTests`, `AppEnvironmentTests/makeCreatesOnDiskDatabase`
7. Logs contain only the stage, case and code. → reviewer reads `logged(_:stage:)`.
8. The full suite passes with no new warnings.

## Out of scope
- Showing the message in the launch UI (T23).
- Wrapping `makeInMemory()` errors.
- Repair or reset actions.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
