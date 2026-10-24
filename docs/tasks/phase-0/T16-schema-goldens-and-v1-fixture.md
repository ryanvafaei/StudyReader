# T16: Schema golden for v1 and a populated v1 fixture database

- **Phase:** 0 (fix from bug hunt `docs/bugs/phase-0.md` M1)
- **Agent:** data-layer
- **Depends on:** T14
- **ADRs:** docs/decisions/0013-schema-migration-policy-v2.md, docs/decisions/0012-data-layer-conventions.md
- **Visual check needed:** no

## Goal
Migration `v1` is applied on the user's real library. Today, an edit to `SchemaV1` passes every test while the user's database never changes. This task:
- pins the v1 schema with a golden dump and a test;
- adds `V1FixtureDatabase`, a populated v1-only database built from frozen raw SQL, which T19 and later migrations use for upgrade tests;
- adds `SearchSamples`, exact search test strings (ligatures, soft hyphens, diacritics) used by T18 and T19. App content is English-only for now (ADR-0014); there are no Persian/Arabic samples.

Tests and test support only. **Don't edit any file in `StudyReader/`**, and in particular not `SchemaV1.swift`.

## Files to touch
- `StudyReaderTests/Support/SchemaSnapshot.swift` (new)
- `StudyReaderTests/Support/V1FixtureDatabase.swift` (new)
- `StudyReaderTests/Support/SearchSamples.swift` (new)
- `StudyReaderTests/Fixtures/schema/v1.sql` (new; generated, see Step 3)
- `StudyReaderTests/CoreTests/SchemaSnapshotTests.swift` (new)
- `StudyReaderTests/CoreTests/V1FixtureDatabaseTests.swift` (new)

`StudyReaderTests/Fixtures` is a folder reference (ADR-0011), so the new `schema/` subfolder is bundled without any `project.yml` change.

## Step 1: `SearchSamples.swift` (copy exactly; escapes keep invisible and look-alike characters exact)
```swift
/// Search test strings as Unicode escapes (ADR-0014). Never retype these as literal characters.
enum SearchSamples {
    /// "photo\u{00AD}synthesis": a soft hyphen U+00AD after "photo", as PDFs store hyphenation points (15 UTF-16 units)
    static let photosynthesisSoftHyphen = "photo\u{00AD}synthesis"
    /// "photosynthesis" as typed (14 UTF-16 units)
    static let photosynthesisPlain = "photosynthesis"
    /// "photos", a prefix of photosynthesisPlain
    static let photosynthesisPrefix = "photos"
    /// "ﬁnd" with U+FB01 LATIN SMALL LIGATURE FI, common in PDF text extraction (3 UTF-16 units)
    static let findLigature = "\u{FB01}nd"
    /// "ﬂow" with U+FB02 LATIN SMALL LIGATURE FL (3 UTF-16 units)
    static let flowLigature = "\u{FB02}ow"
    /// "résumé" decomposed (NFD): "e" + U+0301 combining acute (8 UTF-16 units)
    static let resumeDecomposed = "re\u{0301}sume\u{0301}"
    /// "Résumé" precomposed with U+00E9 and a capital R (6 UTF-16 units)
    static let resumeCapitalPrecomposed = "R\u{00E9}sum\u{00E9}"
    /// "Núñez" precomposed with U+00FA and U+00F1 (5 UTF-16 units)
    static let authorWithDiacritics = "N\u{00FA}\u{00F1}ez"
}
```

## Step 2: `SchemaSnapshot.swift` (`import Foundation`, `import GRDB`, `@testable import StudyReader`)
```swift
enum SchemaSnapshotError: Error { case missingGolden(String) }

enum SchemaSnapshot {
    /// One line per schema object, sorted by type then name:
    /// "<type>|<name>|<tbl_name>|<sql with every whitespace run collapsed to one space>".
    /// Query: SELECT type, name, tbl_name, sql FROM sqlite_master
    ///        WHERE sql IS NOT NULL AND name NOT GLOB 'sqlite_*' AND name NOT GLOB 'grdb_*'
    ///        ORDER BY type, name
    /// Collapse with sql.split(whereSeparator: \.isWhitespace).joined(separator: " ").
    /// Lines joined with "\n", plus one trailing "\n".
    static func dump(_ db: Database) throws -> String

    /// Fresh DatabaseQueue(configuration: AppDatabase.makeConfiguration()), then
    /// AppDatabase.migrator.migrate(queue, upTo: migration), then dump.
    static func dumpAfterMigrating(upTo migration: String) throws -> String

    /// Bundle(for: BundleToken.self).url(forResource: name, withExtension: "sql", subdirectory: "Fixtures/schema"),
    /// read as UTF-8. Throws .missingGolden(name) if absent. (Private `final class BundleToken {}` in this file.)
    static func golden(_ name: String) throws -> String

    /// Writes text to FileManager.default.temporaryDirectory/StudyReaderSchema/<name>.actual.sql
    /// (creating the folder) and returns its URL, or nil if writing fails.
    static func writeActual(_ text: String, name: String) -> URL?

    /// Compares dumpAfterMigrating(upTo: migration) with golden(migration). On any difference (or a missing golden)
    /// calls writeActual and records ONE issue:
    /// "Schema <migration> differs from Fixtures/schema/<migration>.sql. Actual dump: <path>. If you edited a
    ///  committed migration, revert the edit (ADR-0013); never regenerate a committed golden."
    static func expectMatchesGolden(migration: String) throws
}
```
`expectMatchesGolden` uses `Issue.record`, so the file also imports `Testing`.

## Step 3: generate `v1.sql` (once, never by hand)
1. Write the test `v1IsFrozen` (below), without the golden file yet. Run `./scripts/test.sh StudyReaderTests/SchemaSnapshotTests`. The test fails and the issue prints the path of `v1.actual.sql`, under the app container's `tmp`.
2. Read that file and write its exact contents to `StudyReaderTests/Fixtures/schema/v1.sql`. Keep the trailing newline, and don't reformat anything.
3. Run the test again. It must pass.

Expected contents (for your report, not for hand-writing):
- 13 tables, 4 FTS5 virtual tables and their shadow tables (`*_fts_data`, `_idx`, `_docsize`, `_config`);
- the 4 indexes from SchemaV1;
- 12 GRDB triggers named `__<fts>_ai/_ad/_au`.
List the line count in the report.

## Step 4: `V1FixtureDatabase.swift` (`import Foundation`, `import GRDB`, `@testable import StudyReader`)
Frozen raw SQL. Never use record types here: records follow the latest schema, and this file must keep describing v1. Copy this code:
```swift
/// A populated database at migration v1 only (ADR-0013). Frozen: never edit the rows below.
enum V1FixtureDatabase {
    static let documentPDF = "A1000000-0000-4000-8000-000000000001"
    static let documentMarkdown = "A1000000-0000-4000-8000-000000000002"
    static let highlightLatin = "B1000000-0000-4000-8000-000000000001"
    static let highlightMarkdown = "B1000000-0000-4000-8000-000000000002"
    static let tag = "C1000000-0000-4000-8000-000000000001"
    static let card = "D1000000-0000-4000-8000-000000000001"
    static let themedReview = "E1000000-0000-4000-8000-000000000001"
    static let logDaily = "F1000000-0000-4000-8000-000000000001"
    static let logThemed = "F1000000-0000-4000-8000-000000000002"
    static let exportTarget = "A2000000-0000-4000-8000-000000000001"

    /// findLigature + " " + photosynthesisSoftHyphen (19 UTF-16 units)
    static let markdownHighlightText = SearchSamples.findLigature + " " + SearchSamples.photosynthesisSoftHyphen

    static let expectedRowCounts: [String: Int] = [
        "category": 5, "document": 2, "documentText": 3, "highlight": 2, "tag": 1, "highlightTag": 1,
        "documentTag": 1, "documentNote": 1, "reviewCard": 1, "themedReview": 1, "reviewLog": 2,
        "exportTarget": 1, "highlightEmbedding": 1,
    ]

    /// In-memory queue with AppDatabase.makeConfiguration(), migrated up to "v1", then populated.
    static func make() throws -> DatabaseQueue {
        let queue = try DatabaseQueue(configuration: AppDatabase.makeConfiguration())
        try AppDatabase.migrator.migrate(queue, upTo: "v1")
        try queue.write { db in try populate(db) }
        return queue
    }

    /// Same database on disk at fileStore.databaseURL (root directories created), then closed.
    static func makeOnDisk(fileStore: FileStore) throws {
        try fileStore.createRootDirectories()
        let queue = try DatabaseQueue(
            path: fileStore.databaseURL.path(percentEncoded: false),
            configuration: AppDatabase.makeConfiguration())
        try AppDatabase.migrator.migrate(queue, upTo: "v1")
        try queue.write { db in try populate(db) }
        try queue.close()
    }

    static func populate(_ db: Database) throws {
        let lectureSlides = "00000000-0000-0000-0000-000000000001"
        let notes = "00000000-0000-0000-0000-000000000004"
        try db.execute(sql: """
            INSERT INTO document (id, title, author, categoryId, fileType, fileHash, originalFilename, storedPath,
              pageCount, extractionStatus, extractionVersion, pdfPosition, progress, addedAt, lastOpenedAt)
            VALUES (?, 'Cell Biology', 'Alberts', ?, 'pdf', 'v1-fixture-hash-1', 'cell-biology.pdf', ?,
              2, 'done', 1, '{"pageIndex":1,"offsetY":120.5}', 0.5, 1790000000, 1790003600)
            """, arguments: [documentPDF, lectureSlides, "\(documentPDF)/original.pdf"])
        try db.execute(sql: """
            INSERT INTO document (id, title, author, categoryId, fileType, fileHash, originalFilename, storedPath,
              extractionStatus, extractionVersion, textPosition, addedAt)
            VALUES (?, 'Lecture notes', ?, ?, 'markdown', 'v1-fixture-hash-2', 'notes.md', ?, 'done', 1, 42, 1790000100)
            """, arguments: [documentMarkdown, SearchSamples.authorWithDiacritics, notes, "\(documentMarkdown)/original.md"])
        try db.execute(sql: "INSERT INTO documentText (documentId, unitIndex, startOffset, text) VALUES (?, 0, 0, 'Photosynthesis occurs in chloroplasts')",
                       arguments: [documentPDF])
        try db.execute(sql: """
            INSERT INTO documentText (documentId, unitIndex, startOffset, text, runs)
            VALUES (?, 1, 39, 'The Krebs cycle', '[{"start":4,"length":5,"bold":true,"italic":false,"mono":false}]')
            """, arguments: [documentPDF])
        try db.execute(sql: "INSERT INTO documentText (documentId, unitIndex, startOffset, text) VALUES (?, 0, 0, ?)",
                       arguments: [documentMarkdown, SearchSamples.photosynthesisSoftHyphen])
        try db.execute(sql: """
            INSERT INTO highlight (id, documentId, kind, view, color, text, richText, note, pageIndex, positionKey, anchor, createdAt, updatedAt)
            VALUES (?, ?, 'text', 'pdf', 1, 'Mitochondria produce ATP', 'Mitochondria produce **ATP**', 'exam topic', 0, 500.0,
              '{"type":"pdf","pdf":{"pages":[{"pageIndex":0,"rects":[{"x":72,"y":500,"width":200,"height":14}]}],"text":"Mitochondria produce ATP","prefix":"","suffix":""}}',
              1790000200, 1790000200)
            """, arguments: [highlightLatin, documentPDF])
        let markdownAnchor = #"{"type":"text","text":{"start":0,"length":19,"text":""# + markdownHighlightText
            + #"","prefix":"","suffix":"","sourceVersion":1}}"#
        try db.execute(sql: """
            INSERT INTO highlight (id, documentId, kind, view, color, text, richText, positionKey, anchor, createdAt, updatedAt)
            VALUES (?, ?, 'text', 'markdown', 0, ?, ?, 0, ?, 1790000250, 1790000250)
            """, arguments: [highlightMarkdown, documentMarkdown, markdownHighlightText, markdownHighlightText, markdownAnchor])
        try db.execute(sql: "INSERT INTO tag (id, name, createdAt) VALUES (?, 'Exam', 1790000300)", arguments: [tag])
        try db.execute(sql: "INSERT INTO highlightTag (highlightId, tagId) VALUES (?, ?)", arguments: [highlightLatin, tag])
        try db.execute(sql: "INSERT INTO documentTag (documentId, tagId) VALUES (?, ?)", arguments: [documentPDF, tag])
        try db.execute(sql: "INSERT INTO documentNote (documentId, body, updatedAt) VALUES (?, 'Review before the midterm', 1790000400)",
                       arguments: [documentPDF])
        try db.execute(sql: """
            INSERT INTO reviewCard (id, highlightId, cardType, fsrsCard, dueAt, state, introducedAt, createdAt)
            VALUES (?, ?, 'passive', '{}', 1790086400, 'review', 1790000500, 1790000200)
            """, arguments: [card, highlightLatin])
        try db.execute(sql: """
            INSERT INTO themedReview (id, name, filter, cardsPerSession, interval, orderMode, createdAt)
            VALUES (?, 'Exam week', ?, 20, '{"kind":"daily"}', 'dueFirst', 1790000300)
            """, arguments: [themedReview, #"{"tagIds":["\#(tag)"],"tagMode":"any"}"#])
        try db.execute(sql: """
            INSERT INTO reviewLog (id, cardId, rating, reviewedAt, sessionKind, themedReviewId, fsrsLog)
            VALUES (?, ?, 3, 1790000600, 'daily', NULL, '{}'), (?, ?, 4, 1790001200, 'themed', ?, '{}')
            """, arguments: [logDaily, card, logThemed, card, themedReview])
        try db.execute(sql: """
            INSERT INTO exportTarget (id, title, scope, options, format, keepInSync, lastStatus, createdAt)
            VALUES (?, 'StudyReader – All highlights', '{"kind":"all"}',
              '{"includeNotes":true,"includeDocumentNotes":true,"includeImages":true,"groupBy":"document"}',
              'markdown', 0, 'never', 1790000700)
            """, arguments: [exportTarget])
        try db.execute(sql: """
            INSERT INTO highlightEmbedding (highlightId, modelId, dimension, vector, sourceHash)
            VALUES (?, 'NLEmbedding.sentence.en', 2, x'0000803F00000040', 'v1-fixture-source-hash')
            """, arguments: [highlightLatin])
    }
}
```

## Step 5: tests
`SchemaSnapshotTests` (`@Suite struct SchemaSnapshotTests`; filter `StudyReaderTests/SchemaSnapshotTests`):
- `v1IsFrozen`: `try SchemaSnapshot.expectMatchesGolden(migration: "v1")`.
- `registeredMigrationsInOrder`: `#expect(AppDatabase.migrator.migrations == ["v1"])`. Add the comment: "Append-only (ADR-0013): later migrations add to the end of this list."
- `dumpIsDeterministic`: two calls to `dumpAfterMigrating(upTo: "v1")` return equal strings. The output has no line starting with `table|grdb_migrations` or `table|sqlite_`, and contains a line starting with `table|category|category|CREATE TABLE category (`.

`V1FixtureDatabaseTests` (`@Suite struct V1FixtureDatabaseTests`):
- `fixtureHasOnlyV1Applied`: `make()`, then `AppDatabase.migrator.appliedMigrations(db) == ["v1"]`.
- `fixtureHasExpectedRowCounts`: for each entry of `expectedRowCounts`, `SELECT COUNT(*) FROM <table>` equals the value.
- `fixtureRowsDecodeAsRecords`: fetch all rows of all 13 record types (`DocumentCategory`, `LibraryDocument`, `DocumentText`, `Highlight`, `LibraryTag`, `HighlightTag`, `DocumentTag`, `DocumentNote`, `ReviewCard`, `ReviewLogEntry`, `ThemedReview`, `ExportTarget`, `HighlightEmbedding`). Each count matches `expectedRowCounts`. `Highlight.fetchOne(db, key: highlightMarkdown)?.anchor` equals `.text(TextAnchor(start: 0, length: 19, text: markdownHighlightText, prefix: "", suffix: "", sourceVersion: 1))`, and `markdownHighlightText.utf16.count == 19`.
- `onDiskFixtureReopensAtV1`: `let store = TestFileStore.make(); defer { TestFileStore.remove(store) }`, then `makeOnDisk(fileStore: store)`. Open `DatabaseQueue(path:configuration: AppDatabase.makeConfiguration())` on `store.databaseURL`. Don't use `AppDatabase.makeShared`, because that would migrate. Expect applied `== ["v1"]` and 2 documents.

## Interfaces to produce
`SchemaSnapshot.dump/dumpAfterMigrating/golden/writeActual/expectMatchesGolden`, `V1FixtureDatabase.make/makeOnDisk/populate/expectedRowCounts` and its ID constants, `markdownHighlightText`, `SearchSamples.*`, all exactly as above. T18 and T19 use them.

## Acceptance criteria
1. The v1 schema matches the committed golden, generated from test output. → test `SchemaSnapshotTests/v1IsFrozen`
2. The registered migration list is pinned. → test `SchemaSnapshotTests/registeredMigrationsInOrder`
3. The dump is deterministic and skips SQLite/GRDB internals. → test `SchemaSnapshotTests/dumpIsDeterministic`
4. The fixture database is at v1 only, with the expected rows, and the rows decode with the current record types. → tests `V1FixtureDatabaseTests/fixtureHasOnlyV1Applied`, `fixtureHasExpectedRowCounts`, `fixtureRowsDecodeAsRecords`
5. The on-disk fixture is created and stays at v1. → test `V1FixtureDatabaseTests/onDiskFixtureReopensAtV1`
6. No file under `StudyReader/` changed. → reviewer checks the diff.
7. Mutation check: if a reviewer adds `CREATE INDEX x ON reviewLog(cardId);` to `SchemaV1` locally, `v1IsFrozen` fails. The reviewer confirms this from the dump logic and doesn't commit the change.
8. The full suite passes with no new warnings.

## Out of scope
- Migration `v2` (T19). The tokenizer (T18). FTS integrity checks (T17).
- Any change to `SchemaV1.swift`, `AppDatabase.swift` or records.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, Sonnet (effort medium): APPROVED. Tests 107/107, golden matches SchemaV1 (49 lines), fixture uses frozen raw SQL; mutation check verified by reading.
