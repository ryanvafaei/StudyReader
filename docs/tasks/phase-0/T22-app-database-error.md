# T22: Typed `AppDatabaseError` for opening the library

- **Phase:** 0 (fix from bug hunt `docs/bugs/phase-0.md` L3, data part; also fixes a crash regression from T18)
- **Agent:** data-layer
- **Depends on:** T19
- **ADRs:** none new; ARCHITECTURE §14 (typed errors, `LocalizedError`, no PII in logs); ADR-0014 (tokenizer registration, amended 2026-10-24 for this task)
- **Visual check needed:** no

## Goal
If the library can't be opened or migrated, the launch screen today shows GRDB's raw `description`. That text can include `while executing \`CREATE TABLE …\``. `AppDatabase.makeShared` should throw a typed `AppDatabaseError` with short user-facing messages, and log only the stage and the SQLite result code. T23 shows these messages in the UI.

### T18 regression (found while implementing this task, 2026-10-24)
Since T18, `makeConfiguration()` registers the tokenizer in `prepareDatabase`. `db.add(tokenizer:)` can't throw: it calls GRDB's `FTS5.api(db)`, which prepares `SELECT fts5(?)` and calls `fatalError("FTS5 is not available")` if the prepare fails (GRDB `FTS/FTS5.swift`, `api(_:)`). GRDB runs `prepareDatabase` *before* its own `validateFormat()` check. On a damaged file the prepare fails with SQLITE_NOTADB or SQLITE_CORRUPT, so the app crashes instead of throwing. This affects both junk files and files with a valid SQLite header but corrupt pages.

**Fix (decided):** in the `prepareDatabase` closure, read the schema *before* registering the tokenizer. That read throws an ordinary `DatabaseError` (NOTADB or CORRUPT). It leaves `DatabasePool(path:configuration:)` as a thrown error, and `AppDatabaseError.wrap` maps it to `.damaged`. Once the schema has been read, preparing `SELECT fts5(?)` no longer touches the file. The only remaining `fatalError` is "SQLite built without FTS5", and that is a programmer error, not user data. This one fix covers every connection (pool writer, pool readers, `DatabaseQueue`s). SQLite reports the damage itself, so we don't hand-check header bytes.

## Files to touch
- `StudyReader/Core/Database/AppDatabaseError.swift` (new)
- `StudyReader/Core/Database/AppDatabase.swift` (modify `makeShared` and the `prepareDatabase` closure in `makeConfiguration()`; nothing else)
- `StudyReaderTests/CoreTests/AppDatabaseErrorTests.swift` (new)

Do not touch `SearchTokenizer.swift`.

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

In `makeConfiguration()`, replace only the `prepareDatabase` closure with:
```swift
configuration.prepareDatabase { db in
    // Read the schema first, so a damaged file throws SQLITE_NOTADB/SQLITE_CORRUPT here.
    // db.add(tokenizer:) can't throw: GRDB calls fatalError if `SELECT fts5(?)` fails to prepare (T22).
    _ = try Row.fetchOne(db, sql: "SELECT * FROM sqlite_master LIMIT 1")
    db.add(tokenizer: SearchTokenizer.self)
}
```
Keep `foreignKeysEnabled` and `label` as they are. Leave `init(_:)`, `makeInMemory()` and `migrator` unchanged.

## Tests (`@Suite struct AppDatabaseErrorTests`; every store uses `defer { TestFileStore.remove(store) }`)
- `wrapMapsResultCodes`:
  - `wrap(DatabaseError(resultCode: .SQLITE_NOTADB), stage: .open) == .damaged(code: 26)`;
  - `wrap(DatabaseError(resultCode: .SQLITE_CORRUPT), stage: .migrate) == .damaged(code: 11)`;
  - `wrap(DatabaseError(resultCode: .SQLITE_CANTOPEN), stage: .open) == .cannotOpen(code: 14)`;
  - `wrap(DatabaseError(resultCode: .SQLITE_ERROR), stage: .migrate) == .migrationFailed(code: 1)`;
  - `wrap(CocoaError(.fileWriteNoPermission), stage: .open) == .cannotOpen(code: -1)`;
  - `wrap(AppDatabaseError.folderUnavailable, stage: .migrate) == .folderUnavailable`.
- `damagedFileIsReported`: `createRootDirectories()`, then write 1,024 bytes of `"not a database "` repeated to `store.databaseURL`. `makeShared(fileStore:)` throws an `AppDatabaseError` matching `case .damaged`. Use `#expect(throws: AppDatabaseError.self)`, then pattern-match with `if case .damaged = error {} else { Issue.record(…) }`. (Before the fix, this test crashes the test host.)
- `corruptPagesAreReported` (valid header, garbage body):
  1. `createRootDirectories()`. Open a plain `DatabaseQueue(path: store.databaseURL.path(percentEncoded: false))` with **no** configuration. Run `CREATE TABLE t (x)`, then `try queue.close()`.
  2. Overwrite bytes 100..<512 of the file with `Data(repeating: 0xFF, count: 412)`. Use `let handle = try FileHandle(forUpdating: store.databaseURL)`, `try handle.seek(toOffset: 100)`, `try handle.write(contentsOf:)`, `try handle.close()`. Offset 100 is the b-tree header of page 1 (`sqlite_master`). 512 is the smallest SQLite page size, so the write stays inside page 1.
  3. Guard the fixture: `#expect(try Data(contentsOf: store.databaseURL).prefix(16) == Data("SQLite format 3\u{0}".utf8))`.
  4. `makeShared(fileStore:)` throws an `AppDatabaseError` matching `case .damaged` (same pattern as above).
- `configurationThrowsOnDamagedFile`: write the same 1,024-byte junk file as in `damagedFileIsReported`. `DatabaseQueue(path: store.databaseURL.path(percentEncoded: false), configuration: AppDatabase.makeConfiguration())` throws a `DatabaseError` whose `resultCode == .SQLITE_NOTADB`. Use `#expect(throws: DatabaseError.self)` and check the returned error. This proves the fix lives in the shared configuration, not only in `makeShared`.
- `migrationFailureIsReported`: create a database at `store.databaseURL` with a plain `DatabaseQueue(path:)`. Run `CREATE TABLE category (x)` and close it. `makeShared` throws `.migrationFailed(code: 1)`, because v1 hits "table category already exists".
- `folderFailureIsReported`: write a regular file `blocker` inside a fresh `temporaryDirectory/StudyReaderTests/<UUID>/` folder. Use `FileStore(rootURL: <that folder>/blocker/StudyReader)`. `makeShared` throws `.folderUnavailable`. Remove `<UUID>/` in a `defer`.
- `messagesNeverContainSQL`: for `[.folderUnavailable, .cannotOpen(code: 14), .damaged(code: 26), .migrationFailed(code: 1)]`:
  - `errorDescription` and `recoverySuggestion` are non-empty;
  - neither contains `"SQL"`, `"CREATE"`, `"while executing"`, `"/"` or a digit;
  - `error.localizedDescription == error.errorDescription`.
- `healthyLibraryStillOpens`: `makeShared` on a fresh store succeeds, and `appliedMigrations == ["v1", "v2"]`.

If `corruptPagesAreReported` still crashes the host, or throws something other than `.damaged`, don't change the fixture or add header-byte checks. Report BLOCKED with the crash message or the actual error case.

## Acceptance criteria
1. SQLite and other errors map to the four cases as specified. → test `AppDatabaseErrorTests/wrapMapsResultCodes`
2. A non-database file reports `.damaged` and doesn't crash (T18 regression). → test `AppDatabaseErrorTests/damagedFileIsReported`
3. A file with a valid header and corrupt pages reports `.damaged` and doesn't crash. → test `AppDatabaseErrorTests/corruptPagesAreReported`
4. Every connection built with `makeConfiguration()` throws on a damaged file instead of crashing. → test `AppDatabaseErrorTests/configurationThrowsOnDamagedFile`
5. A failing migration reports `.migrationFailed`. → test `AppDatabaseErrorTests/migrationFailureIsReported`
6. A folder that can't be created reports `.folderUnavailable`. → test `AppDatabaseErrorTests/folderFailureIsReported`
7. User-facing texts contain no SQL, paths or codes. → test `AppDatabaseErrorTests/messagesNeverContainSQL`
8. The normal open path and search are unchanged. → tests `AppDatabaseErrorTests/healthyLibraryStillOpens`, `DatabaseMigrationTests`, `SchemaSnapshotTests`, `SearchTokenizerTests`, `AppEnvironmentTests/makeCreatesOnDiskDatabase`
9. Logs contain only the stage, case and code. → reviewer reads `logged(_:stage:)`.
10. In the `prepareDatabase` closure, the schema read comes before `db.add(tokenizer:)`. → reviewer reads `makeConfiguration()`.
11. The full suite passes with no new warnings.

## Out of scope
- Showing the message in the launch UI (T23).
- Wrapping `makeInMemory()` errors.
- Repair or reset actions.
- Corruption that only shows up later in non-schema pages (that's a normal thrown `DatabaseError` from the failing read or write; Phase 1 error handling).
- Checking header bytes by hand.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, Sonnet (effort medium): APPROVED. Tests 151/151; first attempt BLOCKED (T18 regression: damaged file hit GRDB fatalError), spec amended by architect (schema read before tokenizer registration); logs/messages clean; stray SQL in test.log is system SQLite [logging], not app output.
