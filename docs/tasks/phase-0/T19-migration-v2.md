# T19: Migration v2: FK indexes, `studyreader` FTS tables, column-filtered triggers

- **Phase:** 0 (fix from bug hunt `docs/bugs/phase-0.md` M2, M3 part 2, L5)
- **Agent:** data-layer
- **Depends on:** T16, T17, T18
- **ADRs:** docs/decisions/0013-schema-migration-policy-v2.md (read it in full), docs/decisions/0014-search-tokenizer-english.md (English-only), docs/decisions/0012-data-layer-conventions.md
- **Visual check needed:** no

## Goal
Add migration `v2`. It applies to the user's real library (now at `v1`, 0 documents) and to fresh databases. In one migration it:
- adds indexes for the four FK child columns that lack one (M2);
- recreates the four FTS tables with the `studyreader` tokenizer (M3);
- replaces GRDB's sync triggers with hand-written ones whose update trigger fires only when an indexed column changes (L5);
- rebuilds the indexes.

`SchemaV1.swift` must not change. When this task is committed, `SchemaV2` is frozen too (ADR-0013).

Read first: ADR-0013, `StudyReader/Core/Database/AppDatabase.swift`, `SchemaV1.swift` (read-only), `StudyReaderTests/Support/SchemaSnapshot.swift`, `V1FixtureDatabase.swift`, `FTSIntegrity.swift`, `SearchSamples.swift`.

## Files to touch
- `StudyReader/Core/Database/SchemaV2.swift` (new)
- `StudyReader/Core/Database/AppDatabase.swift` (modify `migrator`: register `"v2"` after `"v1"`)
- `StudyReaderTests/Fixtures/schema/v2.sql` (new; generated like v1.sql in T16 Step 3)
- `StudyReaderTests/CoreTests/SchemaSnapshotTests.swift` (modify: add `v2IsFrozen`, update `registeredMigrationsInOrder`)
- `StudyReaderTests/CoreTests/MigrationV2Tests.swift` (new)
- `StudyReaderTests/CoreTests/DatabaseMigrationTests.swift` (modify `reopeningDoesNotRemigrate`: expect `["v1", "v2"]`)

## Interfaces to produce
```swift
/// Migration `v2` (ADR-0013). Frozen once committed.
enum SchemaV2 {
    static func migrate(_ db: Database) throws { try db.execute(sql: sql) }
    static let sql: String = """ … exactly the SQL below … """
}
```
`AppDatabase.migrator`:
```swift
migrator.registerMigration("v1") { db in try SchemaV1.create(db) }
migrator.registerMigration("v2") { db in try SchemaV2.migrate(db) }
```

### The SQL (copy exactly, in this order)
```sql
-- 1. FK child indexes (M2)
CREATE INDEX document_category ON document(categoryId);
CREATE INDEX documentTag_tag ON documentTag(tagId);
CREATE INDEX reviewLog_card ON reviewLog(cardId, reviewedAt);
CREATE INDEX reviewLog_themedReview ON reviewLog(themedReviewId);

-- 2. Drop GRDB synchronize(withTable:) triggers and v1 FTS tables
DROP TRIGGER "__documentText_fts_ai";
DROP TRIGGER "__documentText_fts_ad";
DROP TRIGGER "__documentText_fts_au";
DROP TRIGGER "__highlight_fts_ai";
DROP TRIGGER "__highlight_fts_ad";
DROP TRIGGER "__highlight_fts_au";
DROP TRIGGER "__documentNote_fts_ai";
DROP TRIGGER "__documentNote_fts_ad";
DROP TRIGGER "__documentNote_fts_au";
DROP TRIGGER "__document_fts_ai";
DROP TRIGGER "__document_fts_ad";
DROP TRIGGER "__document_fts_au";
DROP TABLE documentText_fts;
DROP TABLE highlight_fts;
DROP TABLE documentNote_fts;
DROP TABLE document_fts;

-- 3. FTS tables with the studyreader tokenizer (ADR-0014)
CREATE VIRTUAL TABLE documentText_fts USING fts5(text, content='documentText', tokenize='studyreader');
CREATE VIRTUAL TABLE highlight_fts USING fts5(text, editedText, note, content='highlight', tokenize='studyreader');
CREATE VIRTUAL TABLE documentNote_fts USING fts5(body, content='documentNote', tokenize='studyreader');
CREATE VIRTUAL TABLE document_fts USING fts5(title, author, content='document', tokenize='studyreader');

-- 4. Sync triggers; updates re-index only when an indexed column changes (L5)
CREATE TRIGGER documentText_fts_ai AFTER INSERT ON documentText BEGIN
  INSERT INTO documentText_fts(rowid, text) VALUES (new.rowid, new.text);
END;
CREATE TRIGGER documentText_fts_ad AFTER DELETE ON documentText BEGIN
  INSERT INTO documentText_fts(documentText_fts, rowid, text) VALUES ('delete', old.rowid, old.text);
END;
CREATE TRIGGER documentText_fts_au AFTER UPDATE OF text ON documentText BEGIN
  INSERT INTO documentText_fts(documentText_fts, rowid, text) VALUES ('delete', old.rowid, old.text);
  INSERT INTO documentText_fts(rowid, text) VALUES (new.rowid, new.text);
END;

CREATE TRIGGER highlight_fts_ai AFTER INSERT ON highlight BEGIN
  INSERT INTO highlight_fts(rowid, text, editedText, note) VALUES (new.rowid, new.text, new.editedText, new.note);
END;
CREATE TRIGGER highlight_fts_ad AFTER DELETE ON highlight BEGIN
  INSERT INTO highlight_fts(highlight_fts, rowid, text, editedText, note) VALUES ('delete', old.rowid, old.text, old.editedText, old.note);
END;
CREATE TRIGGER highlight_fts_au AFTER UPDATE OF text, editedText, note ON highlight BEGIN
  INSERT INTO highlight_fts(highlight_fts, rowid, text, editedText, note) VALUES ('delete', old.rowid, old.text, old.editedText, old.note);
  INSERT INTO highlight_fts(rowid, text, editedText, note) VALUES (new.rowid, new.text, new.editedText, new.note);
END;

CREATE TRIGGER documentNote_fts_ai AFTER INSERT ON documentNote BEGIN
  INSERT INTO documentNote_fts(rowid, body) VALUES (new.rowid, new.body);
END;
CREATE TRIGGER documentNote_fts_ad AFTER DELETE ON documentNote BEGIN
  INSERT INTO documentNote_fts(documentNote_fts, rowid, body) VALUES ('delete', old.rowid, old.body);
END;
CREATE TRIGGER documentNote_fts_au AFTER UPDATE OF body ON documentNote BEGIN
  INSERT INTO documentNote_fts(documentNote_fts, rowid, body) VALUES ('delete', old.rowid, old.body);
  INSERT INTO documentNote_fts(rowid, body) VALUES (new.rowid, new.body);
END;

CREATE TRIGGER document_fts_ai AFTER INSERT ON document BEGIN
  INSERT INTO document_fts(rowid, title, author) VALUES (new.rowid, new.title, new.author);
END;
CREATE TRIGGER document_fts_ad AFTER DELETE ON document BEGIN
  INSERT INTO document_fts(document_fts, rowid, title, author) VALUES ('delete', old.rowid, old.title, old.author);
END;
CREATE TRIGGER document_fts_au AFTER UPDATE OF title, author ON document BEGIN
  INSERT INTO document_fts(document_fts, rowid, title, author) VALUES ('delete', old.rowid, old.title, old.author);
  INSERT INTO document_fts(rowid, title, author) VALUES (new.rowid, new.title, new.author);
END;

-- 5. Index existing rows
INSERT INTO documentText_fts(documentText_fts) VALUES ('rebuild');
INSERT INTO highlight_fts(highlight_fts) VALUES ('rebuild');
INSERT INTO documentNote_fts(documentNote_fts) VALUES ('rebuild');
INSERT INTO document_fts(document_fts) VALUES ('rebuild');
```
Use plain `DROP TRIGGER`, not `IF EXISTS`: a wrong name must fail loudly. If a `DROP TRIGGER` fails with "no such trigger", read the real names from the v1 golden (`Fixtures/schema/v1.sql`) and report the difference. Don't guess.

## Golden
Generate `Fixtures/schema/v2.sql` with T16's Step 3 procedure: add the test, run it, copy the `v2.actual.sql` it reports, and run it again. Check it before you commit:
- it has no `__` triggers;
- it has 12 triggers named `<fts>_ai/_ad/_au`;
- the four virtual tables contain `tokenize='studyreader'`;
- the four new indexes are present;
- `v1.sql` is unchanged.

## Tests
`SchemaSnapshotTests`:
- add `v2IsFrozen`: `try SchemaSnapshot.expectMatchesGolden(migration: "v2")`;
- change `registeredMigrationsInOrder` to `["v1", "v2"]`;
- keep `v1IsFrozen`.

`MigrationV2Tests` (`@Suite struct MigrationV2Tests`). Fresh databases use `AppDatabase.makeInMemory()`. Use `S` for `SearchSamples` and `F` for `V1FixtureDatabase`. Quote every MATCH term as `"\"" + term + "\""` (prefix queries as `"\"" + term + "\"*"`).
- `foreignKeyLookupsUseIndexes`: for each pair, run `EXPLAIN QUERY PLAN <query>` and join the `detail` column of all rows. The result contains `"INDEX <name>"`. This matches both `USING INDEX` and `USING COVERING INDEX`.
  - `SELECT * FROM reviewLog WHERE cardId = 'x'` → `reviewLog_card`
  - `SELECT * FROM reviewLog WHERE themedReviewId = 'x'` → `reviewLog_themedReview`
  - `SELECT * FROM documentTag WHERE tagId = 'x'` → `documentTag_tag`
  - `SELECT * FROM document WHERE categoryId = 'x'` → `document_category`
- `ftsTablesUseSearchTokenizer`: `SELECT sql FROM sqlite_master WHERE name = ?` for each of `FTSIntegrity.tables` contains `tokenize='studyreader'`. `SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger' AND name GLOB '__*'` is 0, and there are exactly 12 triggers in total.
- `metadataUpdatesDoNotReindex` (L5): insert `TestData.document` and `TestData.highlight`. Inside one `writer.write`, collect trigger events:
  ```swift
  let traced = Mutex<[String]>([])
  db.trace { event in traced.withLock { $0.append(event.description) } }
  try db.execute(sql: "UPDATE document SET progress = 0.5, lastOpenedAt = 1790000999 WHERE id = ?", arguments: [docId])
  try db.execute(sql: "UPDATE highlight SET color = 2, anchorStatus = 'orphaned' WHERE id = ?", arguments: [hlId])
  db.trace()   // stop tracing
  ```
  Expect no traced string to contain `document_fts_au` or `highlight_fts_au`. Then trace a second batch: `UPDATE document SET title = 'Renamed'` and `UPDATE highlight SET note = 'n'`. Each trigger name now appears in at least one traced string. Trigger invocations are traced as `-- TRIGGER <name>`. End with `FTSIntegrity.check`. `import Synchronization` for `Mutex`.
- `foldedSearchOnLiveTables` (M3 acceptance):
  - Insert `TestData.document(author: S.authorWithDiacritics)`, `TestData.highlight(documentId:, text: S.findLigature + " " + S.photosynthesisSoftHyphen)`, a `DocumentText` with text `S.resumeDecomposed`, and a `DocumentNote` with body `S.flowLigature`.
  - Each of these returns the row: `highlight_fts MATCH` `"find"`, `highlight_fts MATCH` `S.photosynthesisPlain`, `highlight_fts MATCH` prefix `S.photosynthesisPrefix`, `document_fts MATCH` `"nunez"` and `"NUNEZ"`, `documentText_fts MATCH` `"resume"`, `documentNote_fts MATCH` `"flow"`.
  - End with `FTSIntegrity.check`.
- `ftsStaysInSyncThroughWrites`: on a fresh database, insert, update (indexed and non-indexed columns) and delete rows in all four content tables through records. Cascade-delete a document. The FTS counts match what remains, and `FTSIntegrity.check` passes after each phase.
- `upgradesPopulatedV1Database`:
  - `let queue = try F.make()`, then `let database = try AppDatabase(queue)`, which runs v2.
  - `appliedMigrations == ["v1", "v2"]`.
  - Every table in `F.expectedRowCounts` has the same count.
  - `Highlight.fetchOne(db, key: F.highlightMarkdown)?.text == F.markdownHighlightText`.
  - Pre-existing rows are searchable with the new tokenizer (the first two and the fourth fail with the v1 tokenizer, so they prove the `'rebuild'` ran):
    - `highlight_fts` `"find"` → the rowid of `F.highlightMarkdown`;
    - `highlight_fts` `S.photosynthesisPlain` → the rowid of `F.highlightMarkdown`;
    - `highlight_fts` `"exam"` → the rowid of `F.highlightLatin` (note column);
    - `documentText_fts` `S.photosynthesisPlain` → 2 rows (the PDF unit and the soft-hyphenated Markdown unit);
    - `documentText_fts` `"chloroplasts"` → 1 row;
    - `document_fts` `"nunez"` → the rowid of `F.documentMarkdown`;
    - `documentNote_fts` `"midterm"` → 1 row.
  - `FTSIntegrity.check` passes.
- `upgradesOnDiskV1Library` (the user's path):
  - `let store = TestFileStore.make(); defer { TestFileStore.remove(store) }`, then `try F.makeOnDisk(fileStore: store)`.
  - `let database = try AppDatabase.makeShared(fileStore: store)`.
  - applied is `["v1", "v2"]`, `PRAGMA journal_mode` is `wal`, and `highlight_fts` `"find"` returns 1 row through `database.reader.read`, a pool reader.
- `deletingDocumentWithManyLogsCascades`: one document, one highlight, one card, 2,000 `reviewLog` rows (raw SQL in one transaction), then delete the document. `reviewLog` is empty, and `FTSIntegrity.check` passes. No timing assertion.

`DatabaseMigrationTests/reopeningDoesNotRemigrate`: change `applied == ["v1"]` to `["v1", "v2"]`. Change nothing else in that file. The suite's display name "Database migration v1" stays.

## Acceptance criteria
1. FK lookups on the four child columns use the new indexes. → test `MigrationV2Tests/foreignKeyLookupsUseIndexes`
2. All four FTS tables use `studyreader`, and no GRDB sync triggers remain. → test `MigrationV2Tests/ftsTablesUseSearchTokenizer`
3. Updating non-indexed columns doesn't fire FTS update triggers; updating indexed columns does. → test `MigrationV2Tests/metadataUpdatesDoNotReindex`
4. Typed queries find ligature, soft-hyphen, diacritic and mixed-case text in all four live FTS tables. → test `MigrationV2Tests/foldedSearchOnLiveTables`
5. FTS stays consistent through inserts, updates, deletes and cascades. → test `MigrationV2Tests/ftsStaysInSyncThroughWrites`
6. A populated v1 database upgrades with no data loss, and its existing rows are searchable with the new tokenizer, in memory and on disk (pool/WAL). → tests `MigrationV2Tests/upgradesPopulatedV1Database`, `MigrationV2Tests/upgradesOnDiskV1Library`
7. A cascade over many review logs works. → test `MigrationV2Tests/deletingDocumentWithManyLogsCascades`
8. v1 is unchanged and v2 is pinned. → tests `SchemaSnapshotTests/v1IsFrozen`, `SchemaSnapshotTests/v2IsFrozen`, `SchemaSnapshotTests/registeredMigrationsInOrder`
9. Existing FTS and migration tests pass unchanged, except the applied list. → `FTSSchemaTests`, `FTSIntegrityTests`, `RecordRoundTripTests`, `DatabaseMigrationTests`
10. `git diff` shows no change to `SchemaV1.swift` or `Fixtures/schema/v1.sql`. → reviewer checks.
11. The full suite passes with no new warnings.

## Out of scope
- Any edit to `SchemaV1`, the tokenizer (T18), or records.
- Search services and the query parser (Phase 1).
- Changing `FTSSchemaTests`' suite name or expectations.

## Notes for the orchestrator
After this task is committed, the user's library gets `v2` on the next launch. That is intended. From then on, `SchemaV2` is frozen like `SchemaV1`.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, Sonnet (effort medium): CHANGES REQUESTED. Migration correct; MigrationV2Tests.foldedSearchOnLiveTables prefix check on highlight_fts is inverted (quoted literal '*', asserts 0 instead of 1).
- 2026-10-24, Sonnet (effort high; Haiku re-run at high): APPROVED. Prefix check fixed (real prefix, asserts 1); tests 133/133; migration, triggers, v2 golden re-confirmed.
