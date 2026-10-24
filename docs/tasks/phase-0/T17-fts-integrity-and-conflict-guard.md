# T17: FTS integrity helper and REPLACE conflict-policy guard

- **Phase:** 0 (fix from bug hunt `docs/bugs/phase-0.md` M5)
- **Agent:** data-layer
- **Depends on:** T16
- **ADRs:** docs/decisions/0012-data-layer-conventions.md (FTS/REPLACE bullet)
- **Visual check needed:** no

## Goal
External-content FTS5 tables can hold stale postings while "word found / not found" checks still pass. One `INSERT OR REPLACE`, or one record with a REPLACE conflict policy, corrupts search silently. This task:
- adds `FTSIntegrity.check(db)`, which runs FTS5 `'integrity-check'` on all four FTS tables;
- calls it at the end of every test that writes indexed tables;
- pins every record's conflict policy to abort.

Tests only. No app code change.

## Files to touch
- `StudyReaderTests/Support/FTSIntegrity.swift` (new)
- `StudyReaderTests/CoreTests/FTSIntegrityTests.swift` (new)
- `StudyReaderTests/CoreTests/RecordConventionTests.swift` (new)
- `StudyReaderTests/CoreTests/FTSSchemaTests.swift` (modify)
- `StudyReaderTests/CoreTests/RecordRoundTripTests.swift` (modify)
- `StudyReaderTests/CoreTests/DatabaseMigrationTests.swift` (modify `deletingDocumentCascades` only)

## Interfaces to produce
```swift
import GRDB

enum FTSIntegrity {
    static let tables = ["documentText_fts", "highlight_fts", "documentNote_fts", "document_fts"]

    /// For each table t: try db.execute(sql: "INSERT INTO \(t)(\(t), rank) VALUES('integrity-check', 1)").
    /// rank = 1 also compares the index with the external content table. Throws DatabaseError
    /// (SQLITE_CORRUPT_VTAB, "database disk image is malformed") on any mismatch. It's a write: call it inside writer.write.
    static func check(_ db: Database) throws
}
```
In tests, call it like this. The `database`/`db` naming follows the existing file, so keep whatever outer name the test already uses:
```swift
try await database.writer.write { db in try FTSIntegrity.check(db) }
```

## Tests
`FTSIntegrityTests` (`@Suite struct FTSIntegrityTests`):
- `cleanDatabasePasses`: `AppDatabase.makeInMemory()`. Insert one document (`TestData.document`), one highlight, one `DocumentText`, one `DocumentNote` through records. Update the highlight note, delete the document, and `FTSIntegrity.check` doesn't throw. Also check that it doesn't throw on the empty database.
- `replaceDesyncIsDetected`: the bug-report scenario, raw SQL:
  ```sql
  INSERT INTO document (id, title, author, categoryId, fileType, fileHash, originalFilename, storedPath, addedAt)
  VALUES ('A0000000-0000-4000-8000-0000000000A1', 'Quantum', '', '<paper id>', 'pdf', 'h1', 'a.pdf', 'A/original.pdf', 1790000000);
  INSERT OR REPLACE INTO document (id, title, author, categoryId, fileType, fileHash, originalFilename, storedPath, addedAt)
  VALUES ('A0000000-0000-4000-8000-0000000000B2', 'Biology', '', '<paper id>', 'pdf', 'h1', 'b.pdf', 'B/original.pdf', 1790000000);
  ```
  Use `BuiltinCategory.paper.id` as an argument. Then `document` has 1 row, and `SELECT COUNT(*) FROM document_fts WHERE document_fts MATCH 'Quantum'` is still 1 (the stale posting). Finally, `FTSIntegrity.check` throws `DatabaseError`: run it in its own `writer.write` inside `await #expect(throws: DatabaseError.self) { … }`. This proves the helper detects desync. Add a comment: "This is why ADR-0012 forbids REPLACE."

`RecordConventionTests` (`@Suite struct RecordConventionTests`):
- `noReplaceConflictPolicy`: for each of the 13 record types (`DocumentCategory`, `LibraryDocument`, `DocumentText`, `Highlight`, `LibraryTag`, `HighlightTag`, `DocumentTag`, `DocumentNote`, `ReviewCard`, `ReviewLogEntry`, `ThemedReview`, `ExportTarget`, `HighlightEmbedding`):
  ```swift
  #expect(T.persistenceConflictPolicy.conflictResolutionForInsert == .abort)
  #expect(T.persistenceConflictPolicy.conflictResolutionForUpdate == .abort)
  ```
  Write one helper `private func expectAbort<T: PersistableRecord>(_: T.Type, sourceLocation: SourceLocation = #_sourceLocation)` and call it 13 times. Pass `sourceLocation` to `#expect`, so a failure points at the right type.

Changes to existing tests (add only; don't change existing expectations):
- `FTSSchemaTests`: at the end of each of the 6 tests, add `try await db.writer.write { db in try FTSIntegrity.check(db) }`. These tests name the `AppDatabase` `db`, and the closure parameter shadows it, which is fine.
  - In `cascadeDeleteClearsIndex`, change the document insert to `insertDocument(db, id: documentId, title: "Okapi")`.
  - Before the delete, expect `matchRowids(db, table: "document_fts", query: "Okapi").count == 1`. After the delete, expect it to be empty. This covers the `document_fts` gap from M5.
- `RecordRoundTripTests`: add the integrity check at the end of `documentRoundTrip`, `documentTextRoundTrip`, `pdfHighlightRoundTrip`, `imageHighlightRoundTrip`, `taggingRoundTrip`, `documentNoteRoundTrip` and `updateKeepsRowAndIndex`.
- `DatabaseMigrationTests/deletingDocumentCascades`: add the integrity check after the delete.

## Acceptance criteria
1. The helper passes on a consistent database. → test `FTSIntegrityTests/cleanDatabasePasses`
2. The helper detects the REPLACE desync from the bug report. → test `FTSIntegrityTests/replaceDesyncIsDetected`
3. No record uses REPLACE for insert or update. → test `RecordConventionTests/noReplaceConflictPolicy`
4. Every listed FTS, round-trip and cascade test ends with an integrity check, and `cascadeDeleteClearsIndex` also checks `document_fts`. → tests in `FTSSchemaTests`, `RecordRoundTripTests`, `DatabaseMigrationTests/deletingDocumentCascades`
5. The full suite passes with no new warnings.

## Out of scope
- App code, schema or migrations (T19 reuses this helper for v2).
- Grepping source code for `INSERT OR REPLACE` from tests (reviewers check this by hand).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, Sonnet (effort medium): APPROVED. Tests 110/110, all 13 record types covered, existing expectations untouched, no app code changed.
