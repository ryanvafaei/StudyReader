# T32: Refuse libraries from newer builds; disk-full and busy messages

- **Phase:** 1 (backlog L5 and L6, `docs/bugs/phase-0-second-pass.md` L5, L6)
- **Agent:** data-layer
- **Depends on:** none
- **ADRs:** docs/decisions/0013-schema-migration-policy-v2.md, ARCHITECTURE §14
- **Visual check needed:** no

## Goal
Phase 1 has no schema change (no `v3`; see the phase README). The user asked for L5 and L6 to ship together with the first `v3`. They ship now instead, without a migration, because the L5 check only protects a library if it is already in the older build: every build from this commit on refuses a library that a later build (with `v3`) migrated. L6 adds error cases in the same type, so both go in one task.

## Files to touch
- `StudyReader/Core/Database/AppDatabaseError.swift` (modify)
- `StudyReader/Core/Database/AppDatabase.swift` (modify)
- `StudyReaderTests/CoreTests/AppDatabaseErrorTests.swift` (modify: add tests, extend `messagesNeverContainSQL`)
- `docs/bugs/backlog.md` (modify: remove L5 and L6, add "fixed by T32" to the section intro)

## Interfaces to produce
New cases in `AppDatabaseError` (keep the existing four unchanged):
```swift
/// The library was migrated by a newer StudyReader build (unknown migration identifiers).
case newerVersion
/// SQLITE_FULL or SQLITE_IOERR at open or migration.
case storageFailure(code: Int32)
/// SQLITE_BUSY or SQLITE_LOCKED at open or migration.
case busy(code: Int32)
```
`wrap(_:stage:)` mapping, in this order:
1. `AppDatabaseError` → unchanged.
2. Non-`DatabaseError` → existing behaviour (code -1).
3. Primary result code `.SQLITE_NOTADB` or `.SQLITE_CORRUPT` → `.damaged(code:)`.
4. `.SQLITE_FULL` or `.SQLITE_IOERR` → `.storageFailure(code:)` (both stages).
5. `.SQLITE_BUSY` or `.SQLITE_LOCKED` → `.busy(code:)` (both stages).
6. Anything else → existing `.cannotOpen` / `.migrationFailed`.

User texts (use `String(localized:)`; no digits, no `/`, no "SQL"):
| Case | errorDescription | recoverySuggestion |
|---|---|---|
| `.newerVersion` | "This library was updated by a newer version of StudyReader." | "Open it with the newer version of StudyReader." |
| `.storageFailure` | "StudyReader couldn't write to its library." | "Check that your Mac has free disk space, then reopen StudyReader." |
| `.busy` | "The library is in use by another copy of StudyReader." | "Quit other copies of StudyReader, then reopen it." |

`AppDatabase.init(_ writer:)`: before `Self.migrator.migrate(writer)`, run
```swift
if try writer.read({ db in try Self.migrator.hasBeenSuperseded(db) }) {
    throw AppDatabaseError.newerVersion
}
```
so both `makeShared` and `makeInMemory` refuse a superseded database, and nothing is migrated or written. `makeShared` already wraps errors from `init` with `wrap`, which returns `AppDatabaseError` unchanged; log it as today.

## Tests (`AppDatabaseErrorTests`)
- `newerLibraryIsRefused`: `TestFileStore.make()` (+ `defer remove`); `_ = try AppDatabase.makeShared(fileStore: store)` and let it go out of scope; open `DatabaseQueue(path: store.databaseURL.path(percentEncoded: false))` (no custom configuration), `INSERT INTO grdb_migrations (identifier) VALUES ('v3')`, close it; then `#expect(throws: AppDatabaseError.newerVersion) { try AppDatabase.makeShared(fileStore: store) }`. Then reopen the queue and check `SELECT identifier FROM grdb_migrations ORDER BY identifier` is still `["v1", "v2", "v3"]` (nothing was migrated or removed).
- `wrapMapsStorageAndBusyCodes`:
  - `wrap(DatabaseError(resultCode: .SQLITE_FULL), stage: .migrate) == .storageFailure(code: 13)`
  - `wrap(DatabaseError(resultCode: .SQLITE_FULL), stage: .open) == .storageFailure(code: 13)`
  - `wrap(DatabaseError(resultCode: .SQLITE_IOERR), stage: .open) == .storageFailure(code: 10)`
  - `wrap(DatabaseError(resultCode: .SQLITE_IOERR_WRITE), stage: .migrate) == .storageFailure(code: 10)` (extended code maps by primary code)
  - `wrap(DatabaseError(resultCode: .SQLITE_BUSY), stage: .open) == .busy(code: 5)`
  - `wrap(DatabaseError(resultCode: .SQLITE_LOCKED), stage: .migrate) == .busy(code: 6)`
- Extend `messagesNeverContainSQL`'s `cases` with `.newerVersion`, `.storageFailure(code: 13)`, `.busy(code: 5)`.

Existing tests stay unchanged and pass (`wrapMapsResultCodes`, `healthyLibraryStillOpens`, …).

## Acceptance criteria
1. A library with an unknown migration is refused before anything is migrated. → test `AppDatabaseErrorTests/newerLibraryIsRefused`
2. Disk and busy failures get their own cases at both stages. → test `AppDatabaseErrorTests/wrapMapsStorageAndBusyCodes`
3. New messages contain no SQL, paths or digits. → test `AppDatabaseErrorTests/messagesNeverContainSQL`
4. `SchemaSnapshotTests` and all existing tests pass; no migration is added (`registeredMigrationsInOrder` still `["v1", "v2"]`).
5. L5 and L6 are removed from `docs/bugs/backlog.md` with "fixed by T32".

## Out of scope
- Any schema change or migration `v3`.
- Changing `LaunchView` (it already shows `errorDescription` + `recoverySuggestion`).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, code-reviewer (sonnet, medium): APPROVED. Matches spec; 171 tests pass. Minor: newerVersion is logged under stage migrate though the check runs before migrating.
