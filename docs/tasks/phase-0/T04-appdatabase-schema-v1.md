# T04: AppDatabase, migration v1 (full schema, FTS5, seed categories)

- **Phase:** 0
- **Agent:** data-layer
- **Depends on:** T02, T03
- **ADRs:** docs/decisions/0003-grdb-fts5-database-of-record.md, docs/decisions/0012-data-layer-conventions.md
- **Visual check needed:** no

## Goal
Create `AppDatabase` (GRDB, WAL on disk, in-memory for tests) and migration `v1` with the complete schema from ARCHITECTURE §4, the four FTS5 external-content tables kept in sync by triggers, and the five built-in categories. Part of epic E0.2. This schema ships to the user's machine and is then frozen (append-only migrations).

Read first: ARCHITECTURE §3 (first bullets), §4 (whole section), ADR-0012.
Optional reference for GRDB migration style only: `.references/reader-source/Reader/Persistence/ReaderLibraryStore.swift` (lines ~750–860). Don't read other reference files.

## Files to touch
- `StudyReader/Core/Database/AppDatabase.swift` (new)
- `StudyReader/Core/Database/SchemaV1.swift` (new)
- `StudyReader/Core/Database/BuiltinCategory.swift` (new)
- `StudyReaderTests/CoreTests/DatabaseMigrationTests.swift` (new)
- `StudyReaderTests/CoreTests/FTSSchemaTests.swift` (new)

## Interfaces to produce

```swift
// AppDatabase.swift
import Foundation
import GRDB

struct AppDatabase: Sendable {
    /// DatabasePool on disk (WAL), DatabaseQueue in memory (ADR-0012).
    let writer: any DatabaseWriter
    var reader: any DatabaseReader { writer }

    /// Runs `AppDatabase.migrator` on `writer`.
    init(_ writer: any DatabaseWriter) throws

    /// Calls fileStore.createRootDirectories(), opens a DatabasePool at fileStore.databaseURL
    /// (path via `path(percentEncoded: false)`) with `makeConfiguration()`, migrates.
    static func makeShared(fileStore: FileStore) throws -> AppDatabase

    /// DatabaseQueue() in memory with `makeConfiguration()`, migrated. Used by all tests.
    static func makeInMemory() throws -> AppDatabase

    /// foreignKeysEnabled = true, label = "StudyReader".
    static func makeConfiguration() -> Configuration

    /// One migration named "v1" that calls SchemaV1.create(_:). Never set eraseDatabaseOnSchemaChange.
    static var migrator: DatabaseMigrator { get }
}

// SchemaV1.swift
enum SchemaV1 {
    static func create(_ db: Database) throws
}

// BuiltinCategory.swift
enum BuiltinCategory: String, CaseIterable, Sendable {
    case lectureSlides, paper, bookChapter, notes, other
    var id: String          // see table
    var name: String        // stored data, not localized
    var frequency: ReviewFrequency
    var sortOrder: Int
}
```

| case | id | name | frequency | sortOrder |
|---|---|---|---|---|
| lectureSlides | `00000000-0000-0000-0000-000000000001` | Lecture slides | high | 0 |
| paper | `00000000-0000-0000-0000-000000000002` | Paper | normal | 1 |
| bookChapter | `00000000-0000-0000-0000-000000000003` | Book chapter | normal | 2 |
| notes | `00000000-0000-0000-0000-000000000004` | Notes | low | 3 |
| other | `00000000-0000-0000-0000-000000000005` | Other | normal | 4 |

## SchemaV1.create steps (in this order, all inside the migration's transaction)
1. Execute the `CREATE TABLE` / `CREATE INDEX` SQL from ARCHITECTURE §4 **verbatim** (same table names, column names, types, defaults, CHECKs, FKs, indexes). You may run it as one `try db.execute(sql: """ ... """)` string. Create tables in this order so every FK target exists first: `category`, `document`, `documentText`, `highlight` (+ index `highlight_document`), `tag`, `highlightTag`, `documentTag` (+ index `highlightTag_tag`), `documentNote`, `reviewCard` (+ indexes `reviewCard_due`, `reviewCard_highlight`), `themedReview`, `reviewLog`, `exportTarget`, `highlightEmbedding`.
2. Create the four FTS5 tables with GRDB (this generates the sync triggers):
   ```swift
   try db.create(virtualTable: "highlight_fts", using: FTS5()) { t in
       t.synchronize(withTable: "highlight")
       t.tokenizer = .unicode61(diacritics: .remove)   // = "unicode61 remove_diacritics 2"
       t.column("text")
       t.column("editedText")
       t.column("note")
   }
   ```
   Same pattern for `documentText_fts` (column `text`, table `documentText`), `documentNote_fts` (`body`, table `documentNote`), `document_fts` (`title`, `author`, table `document`). If `.remove` isn't available in GRDB 7.11, use `FTS5TokenizerDescriptor(components: ["unicode61", "remove_diacritics", "2"])` and say so in your report.
3. Insert one `category` row per `BuiltinCategory.allCases` with arguments: `id`, `name`, `isBuiltin = 1`, `frequency = frequency.rawValue`, `autoCreateCards = 1`, `sortOrder`. Use statement arguments (`arguments: [...]`), never string interpolation.

No other tables, columns, triggers, or seed rows.

## Test notes
- Records (Swift types) don't exist yet: tests insert rows with raw SQL via `try await db.writer.write { try $0.execute(sql:arguments:) }` and read with `Row`/`Int.fetchOne`/`String.fetchAll`.
- Use whole-second dates (e.g. `1_790_000_000.0`) for REAL date columns.
- A minimal valid document row: `INSERT INTO document (id, title, categoryId, fileType, fileHash, originalFilename, storedPath, addedAt) VALUES (?, 'Doc', '00000000-0000-0000-0000-000000000001', 'pdf', ?, 'doc.pdf', ?, 1790000000)`.
- External-content FTS: check the index with `SELECT rowid FROM highlight_fts WHERE highlight_fts MATCH ?` and compare to `SELECT rowid FROM highlight WHERE id = ?`. Pass the MATCH text as an argument.
- On-disk tests use `TestFileStore.make()` (T02).

## Acceptance criteria
1. After migration, `sqlite_master` contains all 13 tables, the 4 FTS tables, and the indexes `highlight_document`, `highlightTag_tag`, `reviewCard_due`, `reviewCard_highlight`. → test `DatabaseMigrationTests/v1CreatesAllTables`
2. Exactly 5 categories, matching the BuiltinCategory table (id, name, frequency, sortOrder, `isBuiltin = 1`, `autoCreateCards = 1`). → test `DatabaseMigrationTests/v1SeedsBuiltinCategories`
3. Opening `makeShared` twice on the same `TestFileStore` succeeds and still yields 5 categories; `DatabaseMigrator.appliedIdentifiers` (or `completedMigrations`) is `["v1"]`. → test `DatabaseMigrationTests/reopeningDoesNotRemigrate`
4. On-disk database uses WAL: `PRAGMA journal_mode` returns `"wal"`; the file exists at `fileStore.databaseURL`. → test `DatabaseMigrationTests/onDiskDatabaseUsesWAL`
5. Inserting a `highlight` with a non-existent `documentId` throws. → test `DatabaseMigrationTests/foreignKeysEnforced`
6. CHECK constraints reject bad values: `document.fileType = 'docx'`, `highlight.color = 5`, `category.frequency = 'sometimes'`. → test `DatabaseMigrationTests/checkConstraintsEnforced`
7. Deleting a `document` removes its rows in `documentText`, `highlight`, `highlightTag`, `documentTag`, `documentNote`, `reviewCard`, `reviewLog`, `highlightEmbedding` (insert one of each first); the `tag` row survives. → test `DatabaseMigrationTests/deletingDocumentCascades`
8. Deleting a category that a document uses throws (ON DELETE RESTRICT). → test `DatabaseMigrationTests/categoryDeleteRestricted`
9. `highlight_fts` follows insert, update (note "alpha" → "beta": 'alpha' 0 hits, 'beta' 1 hit), and delete of a highlight. → test `FTSSchemaTests/highlightIndexFollowsChanges`
10. `documentText`, `documentNote`, and `document` (title and author) rows are findable through their FTS tables. → tests `FTSSchemaTests/documentTextIndexed`, `FTSSchemaTests/documentNoteIndexed`, `FTSSchemaTests/documentTitleAuthorIndexed`
11. After deleting a document, MATCH on its highlight, page text, and note returns no rowids (cascade fires the delete triggers). → test `FTSSchemaTests/cascadeDeleteClearsIndex`
12. A highlight with text "café résumé" is found by MATCH `cafe` and by `resume`. → test `FTSSchemaTests/diacriticsRemoved`

## Out of scope
- Swift record types (T05, T06), repositories (T07), search service and query parser (Phase 1).
- Any change to the ARCHITECTURE §4 schema. If something in it doesn't work in SQLite, report BLOCKED.

## Review log
<!-- Main session appends one line per review: date, model used, verdict, short reason -->
- 2026-10-23, Sonnet (effort medium): APPROVED. Tests 36/36, schema identical to ARCHITECTURE §4, FTS triggers and seeds verified. Minor: categoryDeleteRestricted should assert SQLITE_CONSTRAINT; cascade test doesn't cover document_fts.
