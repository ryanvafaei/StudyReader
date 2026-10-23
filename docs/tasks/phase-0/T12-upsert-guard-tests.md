# T12: Guard tests for primary-key-only upsert

- **Phase:** 0 (fix from bug hunt `docs/bugs/phase-0.md` H1)
- **Agent:** data-layer
- **Depends on:** T05, T07
- **ADRs:** docs/decisions/0012-data-layer-conventions.md (amended 2026-10-24, "Writes" and "Dedupe" bullets)
- **Visual check needed:** no

## Goal
GRDB's default `upsert(db)` reacts to every UNIQUE constraint. A second document with the same `fileHash` (or a tag with the same name in different case) silently overwrites the existing row, and no error is raised. ADR-0012 now allows upsert only with the primary key as conflict target. This task adds tests that pin the safe behaviour so later code can't regress it, and confirms no current code uses the default upsert. Tests only: no schema change, no new migration, no app code change.

Read first: ADR-0012 (the two bullets above), `StudyReaderTests/CoreTests/DocumentRepositoryTests.swift`, `StudyReaderTests/Support/TestData.swift` (`document(...)`, `tag(...)`).

## Files to touch
- `StudyReaderTests/CoreTests/UpsertConventionTests.swift` (new)
- `StudyReaderTests/CoreTests/DocumentRepositoryTests.swift` (modify: add one test)

## Step 1: check existing code
Search `StudyReader/` and `StudyReaderTests/` for `upsert` (this covers `upsert(` and `upsertAndFetch(`). At planning time there were no matches. In your report, list every match outside the new test file. If one is in app code and has no `onConflict:`, don't fix it. Report it as a finding, because changing it changes behaviour.

## Step 2: tests
Use `AppDatabase.makeInMemory()` and write through `database.writer.write { db in … }`. Name the `AppDatabase` value `database` so it doesn't shadow the closure's `db`. Use these fixed ids:
```swift
let idA = "10000000-0000-0000-0000-0000000000a1"
let idB = "10000000-0000-0000-0000-0000000000a2"
```
The only allowed upsert call shape is:
```swift
_ = try record.upsertAndFetch(db, onConflict: ["id"])
```
`upsertAndFetch` isn't `@discardableResult`. Don't call `upsert(db)` anywhere, not even to show the bug.

To assert the error is a uniqueness violation, use:
```swift
let error = await #expect(throws: DatabaseError.self) { try await database.writer.write { db in … } }
#expect(error?.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE)
```
If your toolchain's `#expect(throws:)` doesn't return the error, use `do/catch` with `Issue.record` in the no-throw path. Don't loosen the check.

`UpsertConventionTests` (`@Suite("UpsertConvention")`):
- `primaryKeyUpsertInsertsNewRow`: on an empty database, upsert `TestData.document(id: idA)` with `onConflict: ["id"]`. The returned record equals the input, and `LibraryDocument.fetchOne(db, key: idA)` equals it.
- `primaryKeyUpsertUpdatesExistingRow`: insert A. Copy it, set `title = "Renamed"`, and upsert the copy with `onConflict: ["id"]`. Then `fetchOne(key: idA)?.title == "Renamed"`, `storedPath` is unchanged, and `LibraryDocument.fetchCount(db) == 1`.
- `primaryKeyUpsertWithDuplicateFileHashThrows`: insert `A = TestData.document(id: idA, title: "Quantum", fileHash: "same")`. Upsert `TestData.document(id: idB, title: "Biology", fileHash: "same")` with `onConflict: ["id"]`. It throws `DatabaseError` with `.SQLITE_CONSTRAINT_UNIQUE`. Afterwards `fetchOne(key: idA) == A` (whole record equal, so `storedPath` is still `"\(idA)/original.pdf"`), `fetchOne(key: idB) == nil`, and `fetchCount == 1`.
- `primaryKeyUpsertWithDuplicateTagNameThrows`: insert `TestData.tag(name: "Exam", id: idA)`. Upsert `TestData.tag(name: "exam", id: idB)` with `onConflict: ["id"]`. It throws with `.SQLITE_CONSTRAINT_UNIQUE`. Afterwards `LibraryTag.fetchOne(db, key: idA)?.name == "Exam"`, `LibraryTag.fetchOne(db, key: idB) == nil`, and `LibraryTag.fetchCount(db) == 1`.
- `saveWithDuplicateFileHashThrows`: insert A as in the fileHash test, then `try B.save(db)` (B has the same hash and a new id). It throws `DatabaseError` with `.SQLITE_CONSTRAINT_UNIQUE`, A is unchanged (whole record equal), and B is absent. If `save` throws a different error type, report it. Don't change the expectation.

`DocumentRepositoryTests` (add one test, keep the existing ones as they are):
- `duplicateHashInsertKeepsExistingRow`: through `DocumentRepository`, insert A (`fileHash: "same"`). Then `repo.insert(B)` with the same hash throws `DatabaseError`. Afterwards `repo.fetch(id: idA) == A`, `repo.fetch(id: idB) == nil`, and `repo.fetchAll().count == 1`. This is the path a Phase 1 import (SPEC F-02 AC 2, "Importing the same file twice keeps one document") goes through.

## Acceptance criteria
1. A primary-key upsert inserts when the row is missing. → test `UpsertConventionTests/primaryKeyUpsertInsertsNewRow`
2. A primary-key upsert updates the existing row with the same id. → test `UpsertConventionTests/primaryKeyUpsertUpdatesExistingRow`
3. A primary-key upsert that conflicts on `document.fileHash` throws a UNIQUE error, and neither row is changed or created. → test `UpsertConventionTests/primaryKeyUpsertWithDuplicateFileHashThrows`
4. A primary-key upsert that conflicts on `tag.name` (NOCASE) throws, and the existing tag keeps its name. → test `UpsertConventionTests/primaryKeyUpsertWithDuplicateTagNameThrows`
5. `save` with a duplicate `fileHash` throws and leaves the existing row unchanged. → test `UpsertConventionTests/saveWithDuplicateFileHashThrows`
6. A duplicate-hash insert through `DocumentRepository` keeps the original row and creates no new one. → test `DocumentRepositoryTests/duplicateHashInsertKeepsExistingRow`
7. The report lists the results of the `upsert` search from Step 1 (expected: only the new tests).
8. The full suite passes with no new warnings.

## Out of scope
- Schema changes, a `v2` migration, and any edit to `SchemaV1.swift`. A v2 migration is a separate decision for the user (bug report M1, M2, M3).
- New repository methods (`upsert`, dedupe-by-hash import). Phase 1 adds those and must follow the ADR-0012 "Dedupe" bullet.
- The other bug-hunt findings (M1–M5, L1–L7).
- Any app code change.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, Sonnet (effort medium): APPROVED. Tests 93/93; tests guard H1 (duplicate fileHash/tag name throw, original row unchanged); no upsert elsewhere. Note: scripts/test.sh filters need struct names, not @Suite display names.
