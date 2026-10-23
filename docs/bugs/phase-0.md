# Phase 0 bug hunt

- Date: 2026-10-24
- Scope: commits through T11 (`ffbdb22`): `StudyReader/`, `StudyReaderTests/`, `project.yml`, `StudyReader/Core/Database/`, ADR-0011, ADR-0012.
- Baseline: `./scripts/test.sh` gives 87 tests in 20 suites, all passing, no compiler warnings in project code.
- Hand diff of `SchemaV1.swift` against ARCHITECTURE §4: identical except that `themedReview` is created before `reviewLog` (needed for the FK). FTS tokenizer resolves to `remove_diacritics 2` (GRDB `FTS5TokenizerDescriptor.swift:187`).
- Test-host isolation works today. The real library (`~/Library/Containers/com.ryanvafaei.StudyReader/Data/Library/Application Support/StudyReader/`) was created at 2026-10-23 20:54 by the T08 visual check, and none of the later test runs (00:55, 00:57, 01:15, 01:21) touched `StudyReader.sqlite`, `-wal` or `-shm`.
- **Important for fix tasks:** the real library already has migration `v1` applied (`grdb_migrations` = `v1`, 0 documents; checked read-only). Under ARCHITECTURE §4 "Migration rules", `v1` has now shipped. Any schema fix below must go into a new migration (`v2`), unless the user decides to delete the dev library and keep editing `v1`. Editing `SchemaV1.swift` would pass every test and never reach the user's database (see M1).

Counts: critical 0, high 1, medium 5, low 7.

---

## High

### H1. ADR-0012 tells implementers to use `upsert`, and GRDB's default upsert silently overwrites a different row when a secondary UNIQUE constraint conflicts
- **Severity:** high. ADRs are binding ("follow them, don't re-decide them"). The first Phase 1 code that dedupes imports (SPEC F-02 AC 2, "Importing the same file twice keeps one document") or creates tags or categories by name will lose data silently if it follows the ADR. There is no error and no test failure, because the call "succeeds".
- **Location:** `docs/decisions/0012-data-layer-conventions.md:18` ("use `update`/`upsert`/`save`"). Affected schema: `StudyReader/Core/Database/SchemaV1.swift:24` (`document.fileHash UNIQUE`), `:11` (`category.name UNIQUE COLLATE NOCASE`), `:69` (`tag.name UNIQUE COLLATE NOCASE`). GRDB behaviour: `GRDB/Record/PersistableRecord+Upsert.swift:5-10` (doc comment: "triggered by a violation of any uniqueness constraint … all columns but the primary key are overwritten"). SQL is built in `GRDB/Record/MutablePersistableRecord+DAO.swift:64-90`.
- **Reproduction:** confirmed with SQLite 3.54 using the exact statement shape GRDB generates:
  1. Insert document `id='A', title='Quantum', fileHash='h1'`.
  2. `INSERT INTO document (id,title,author,fileHash) VALUES ('B','Biology','','h1') ON CONFLICT DO UPDATE SET title=excluded.title, …`
  3. Result: one row, `id='A', title='Biology'`. The caller believes document `B` exists, but `fetch(id: "B")` returns nil. Row A's `storedPath` now points at `B/original.<ext>`, and `extractionStatus`, `pdfPosition`, `addedAt` and `categoryId` are reset.
  
  The ARCHITECTURE §13 launch cleanup ("remove `Documents/<id>` folders with no `document` row") would then delete `Documents/B/`, which is the folder row A now points to.
  
  The same thing happens with tags: upserting `('T2','exam')` against an existing `('T1','Exam')` leaves `T1` renamed to `exam`, and `T2` is never created.
  
  With an explicit target (`ON CONFLICT(id)`), the fileHash conflict raises `UNIQUE constraint failed`, which is correct.
- **Failing test:** in `DocumentRepositoryTests`, insert `TestData.document(id: A, fileHash: "same")`, then `try TestData.document(id: B, fileHash: "same").upsert(db)`. Expect a thrown `DatabaseError`. Actual: no throw, `fetch(id: B) == nil`, and `fetch(id: A)?.storedPath == "B/original.pdf"`.
- **Fix direction:** amend ADR-0012: "upsert only with `onConflict: [primary key columns]` (or never on tables with secondary UNIQUE constraints); prefer `save`/`update`". Add the test above as a guard.
- **Owner:** architect (ADR amendment), then data-layer (guard test).

---

## Medium

### M1. Nothing stops anyone from editing the frozen migration `v1`, and there is no frozen v1 fixture for future migration tests
- **Severity:** medium. `v1` is already on the user's machine. Bug-fix tasks are about to touch the schema (M2, M3). An implementer who edits `SchemaV1.create` instead of adding `v2` gets green tests on fresh databases, but the user's library keeps the old schema forever (GRDB never reruns an applied migration). The fresh-DB and real-DB schemas diverge silently, including CHECK constraints, FK actions and FTS configuration.
- **Location:** `StudyReader/Core/Database/AppDatabase.swift:39-45`, `StudyReader/Core/Database/SchemaV1.swift:7`. Rule: `docs/ARCHITECTURE.md:315`.
- **Reproduction:** add `CREATE INDEX reviewLog_card ON reviewLog(cardId)` inside `SchemaV1.create`, then run `./scripts/test.sh`. All 87 tests pass. Launch the app against the existing library: `PRAGMA index_list(reviewLog)` is still empty.
- **Failing-test description:** a `SchemaV1SnapshotTests/v1IsFrozen` test that applies only `v1` (`migrator.migrate(db, upTo: "v1")`), dumps `SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY name`, and compares the dump with a committed golden file (`Fixtures/schema/v1.sql`). Today no such test exists, so an edit goes unnoticed.
- **Fix direction:** add the golden snapshot test now, plus a helper that builds a populated v1-only database, so each later migration can satisfy the §4 rule "test that migrates a populated v1 database".
- **Owner:** data-layer.

### M2. FK child columns without indexes: `reviewLog.cardId`, `reviewLog.themedReviewId`, `documentTag.tagId`, `document.categoryId`
- **Severity:** medium. Every cascade, SET NULL or RESTRICT check on these FKs does a full table scan of the child table, once per parent row deleted. `reviewLog` only grows (one row per review), so deleting a document with N cards costs N full scans of `reviewLog`. Phase 2 queries for the log entries of one card (FSRS history, mastery) also scan.
- **Location:** `StudyReader/Core/Database/SchemaV1.swift:113-120` (reviewLog), `:74-78` (documentTag; only `highlightTag_tag` was added), `:22` (document.categoryId).
- **Reproduction:** run the v1 DDL in `sqlite3` and check `EXPLAIN QUERY PLAN`:
  - `SELECT * FROM reviewLog WHERE cardId='x'` gives `SCAN reviewLog`.
  - The same happens for `reviewLog WHERE themedReviewId=…`, `documentTag WHERE tagId=…` and `document WHERE categoryId=…`. These are the lookups SQLite runs for FK actions.
  - Failing test: seed 1 document, 300 highlights with cards, and 50,000 `reviewLog` rows, then delete the document. Expect it to finish in under 0.5 s; time grows as cards × logs.
- **Fix direction:** add a `v2` migration with `CREATE INDEX` on the four columns (cheap, and safe on the existing library). Assert the indexes exist in `DatabaseMigrationTests`.
- **Owner:** data-layer.

### M3. FTS tokenizer can't find Persian/Arabic words with ZWNJ, harakat, or Arabic letter forms of yeh/kaf
- **Severity:** medium. SPEC §non-functional (`docs/SPEC.md:402`) requires Persian content to work, and the user's fixtures include Persian. With the v1 tokenizer, everyday Persian queries miss matches. The tokenizer lives in v1, so fixing it later needs a migration that drops, recreates and rebuilds the four FTS tables. It is cheap now (the library is empty) and costs more with each Phase 1 import.
- **Location:** `StudyReader/Core/Database/SchemaV1.swift:144-169` (`.unicode61(diacritics: .remove)` on all four FTS tables). Design source: `docs/ARCHITECTURE.md:309`.
- **Reproduction:** FTS5 with `tokenize='unicode61 remove_diacritics 2'`, checked against the SQLite library:
  - `می‌خواهم` (with U+200C) is indexed as two tokens, `می` and `خواهم`. MATCH `میخواهم` (typed without ZWNJ) returns 0 rows.
  - `كِتَاب` (with kasra and fatha, category Mn) is indexed as `ك`, `ت`, `اب`. MATCH `كتاب` returns 0 rows.
  - `كتاب علي` (Arabic kaf U+0643, Arabic yeh U+064A, common in PDFs) does not match the Persian-keyboard query `کتاب` (U+06A9) or `علی` (U+06CC). Both return 0 rows.
  
  NFD Latin text is fine: an NFD `résumé` matches `resume`.
- **Failing test:** in `FTSSchemaTests`, insert a highlight with text `كتاب می‌خواهم`, then MATCH `کتاب` and `میخواهم`. Each should return the row; today both return nothing.
- **Fix direction:** decide (ADR) between a GRDB `FTS5WrapperTokenizer` around unicode61 and normalizing in `SearchQueryParser` plus the indexed text. The wrapper would drop ZWNJ and Arabic marks (U+064B–U+065F, U+0670) and fold ي→ی and ك→ک. Ship it as a `v2` migration that recreates and `'rebuild'`s the FTS tables, together with L5.
- **Owner:** architect (decision), then data-layer.

### M4. Test-host isolation rests on two environment-variable names, and no test checks that the real hosted process is detected
- **Severity:** medium. If Xcode changes how it launches the host, the app silently opens and migrates the user's real library during every test run, and the suite stays green. This is the one Phase 0 guarantee that protects user data. XCUITest is allowed by CLAUDE.md:28, and a UI-test-launched app has neither variable, so it would run against the real library.
- **Location:** `StudyReader/App/AppEnvironment.swift:46-48`, `StudyReader/App/AppLaunchModel.swift:21-26`. The only test is `StudyReaderTests/AppTests/AppEnvironmentTests.swift:30-34`, which passes literal dictionaries and never checks `ProcessInfo`.
- **Reproduction:** change `isRunningUnitTests` to check a misspelled key such as `"XCTestConfigurationFilePth"`. All 87 tests still pass: the only detection test passes literal dictionaries, and the other tests build their own environments. Meanwhile `defaultFactory` would take the `live()` branch and open `~/Library/Containers/…/StudyReader/StudyReader.sqlite` during the run. I worked this out from the code and did not run it, so the user's library was not touched.
- **Failing test:** `AppEnvironmentTests/hostedProcessIsDetected`, asserting `#expect(AppEnvironment.isRunningUnitTests())` with the default argument. Tests run inside the host process, so this checks the real environment.
- **Fix direction:** add that test. Also honour an explicit launch argument or env (for example `-StudyReaderInMemory YES`) in `defaultFactory`, so future UI tests can opt in safely.
- **Owner:** ui-builder.

### M5. FTS sync tests can't detect index desync, and the REPLACE/VACUUM rules in ADR-0012 have no guard
- **Severity:** medium. The tests only check that one word is found or not found. External-content FTS5 can be corrupt (stale or missing postings) while those checks still pass. Nothing pins `persistenceConflictPolicy` to abort, so one `static let persistenceConflictPolicy = .init(insert: .replace)` on a record, or an `INSERT OR REPLACE` in a repository, would corrupt search without failing a test.
- **Location:** `StudyReaderTests/CoreTests/FTSSchemaTests.swift` (whole suite). `cascadeDeleteClearsIndex` (`:142-182`) also never checks `document_fts` after the document delete. Rule: `docs/decisions/0012-data-layer-conventions.md:18`.
- **Reproduction:** confirmed in `sqlite3` with the GRDB trigger shape (`GRDB/FTS/FTS5.swift:266-275`). Insert document `('A','Quantum',…,'h1')`, then `INSERT OR REPLACE INTO document VALUES ('B','Biology','','h1')`.
  - Result: one row, but MATCH `Quantum` still returns 1.
  - `INSERT INTO document_fts(document_fts, rank) VALUES('integrity-check', 1)` fails with "database disk image is malformed".
- **Failing-test description:**
  - (a) A helper `assertFTSIntegrity(db)` that runs `'integrity-check'` on all four FTS tables. Call it at the end of every FTS, round-trip and cascade test; it fails on the scenario above.
  - (b) `RecordConventionTests/noReplaceConflictPolicy`, asserting that `persistenceConflictPolicy.conflictResolutionForInsert` and `…ForUpdate` are `.abort` for `LibraryDocument`, `DocumentText`, `Highlight` and `DocumentNote`.
- **Fix direction:** add both tests now. Phase 1 `SearchIndexSyncTests` can reuse the helper.
- **Owner:** data-layer.

---

## Low

### L1. FileStore validates only `create/deleteDocumentFolder`. The other path builders allow `..` traversal, and IDs need not be canonical.
- **Severity:** low. Inputs are app-generated today. But FileStore is "the only code that builds paths", and Phase 1 will delete files by stored relative paths.
- **Location:** `StudyReader/Core/Files/FileStore.swift:42-70` (no validation in `documentFolderURL`, `originalFileURL`, `coverURL`, `imagesFolderURL`, `snapshotURL`, `url(forRelativePath:)`), and `:125-129` (accepts lowercase UUIDs).
- **Reproduction:** confirmed by running Foundation directly:
  - `url(forRelativePath: "../StudyReader.sqlite")` resolves to the library database.
  - `"A/../../../x"` resolves to `…/Application Support/x`.
  - `snapshotURL(documentId: id, highlightId: "../../../../evil")` resolves outside the library root.
  - `createDocumentFolder("6f1c2b7e-…")` (lowercase) is accepted. On case-insensitive APFS it is the same folder as the uppercase ID, while SQLite TEXT keys stay case-sensitive. A Phase 1 orphan sweep comparing `documentFolderIds()` to DB IDs could delete a live folder.
- **Failing test:** `FileStoreTests/rejectsEscapingPaths`. `url(forRelativePath: "../StudyReader.sqlite")` should throw or return nil, and `createDocumentFolder` should reject `id.lowercased()`.
- **Fix direction:**
  - Validate IDs as canonical (`UUID(uuidString: id)?.uuidString == id`) in every builder (throwing variants), including `highlightId`.
  - Make `url(forRelativePath:)` return nil when the standardized result is not under `documentsURL`.
- **Owner:** data-layer.

### L2. The library is opened and migrated synchronously on the main actor
- **Severity:** low now. It becomes a launch hang once migrations, the WAL recovery of a large library, or the §13 launch cleanup are added to the factory. The `.loading` ProgressView never animates, because the main thread is blocked. The T08 reviewer noted this too.
- **Location:** `StudyReader/App/AppLaunchModel.swift:30-38`, called from `StudyReader/App/LaunchView.swift:22` (`.task` on the main actor).
- **Reproduction:** give the factory a `Thread.sleep(forTimeInterval: 3)` to stand in for a slow migration. The window is unresponsive for 3 s with a frozen spinner.
- **Fix direction:** make `start()` async and run the factory off the main actor (`Task.detached` or a nonisolated async helper), keeping the "factory runs once" guard. Update `AppLaunchModelTests` to `await`.
- **Owner:** ui-builder.

### L3. A launch failure shows the raw GRDB error, including SQL, and there is no typed domain error
- **Severity:** low. If a migration fails, `error.localizedDescription` for `DatabaseError` is its `description`: "SQLite error N: … - while executing \`<statement>\`" (`GRDB/Core/DatabaseError.swift:566-572`, `:609-625`). That can be a whole `CREATE TABLE` block shown in the ContentUnavailableView. ARCHITECTURE §14 asks for typed errors with user-facing `LocalizedError` messages.
- **Location:** `StudyReader/App/AppLaunchModel.swift:36`, `StudyReader/Core/Database/AppDatabase.swift:17-24`.
- **Reproduction:** point `AppEnvironment.make` at a FileStore whose `StudyReader.sqlite` is a 1 KB text file, or make migration `v1` throw. The UI shows GRDB's raw `description`, "SQLite error <code>: <message>", with " - while executing \`<sql>\`" appended when a statement failed. The format is taken from the GRDB source; I didn't screenshot this exact message.
- **Fix direction:** wrap failures from `makeShared` in an `AppDatabaseError` (`cannotOpen`, `migrationFailed`, `notADatabase`) with short messages. Log the underlying code with privacy-safe fields.
- **Owner:** data-layer, plus ui-builder for the message.

### L4. Dates round-trip through Unix seconds but not through `==`. About half of real timestamps compare unequal after a save and fetch.
- **Severity:** low. ADR-0012 only makes tests use whole seconds. Production code that compares an in-memory record to its observed or fetched copy will see phantom changes. Examples: "unsaved changes" detection, `removeDuplicates` on a ValueObservation, `fetched == saved` checks with `SystemNow`.
- **Location:** `StudyReader/Core/Models/StudyRecord.swift:14-21` (`.timeIntervalSince1970`). ADR note at `docs/decisions/0012-data-layer-conventions.md:25`.
- **Reproduction:** for 10,000 random dates in the 2026–2029 range, `Date(timeIntervalSince1970: d.timeIntervalSince1970) != d` in 4,625 cases. A failing test: insert `TestData.highlight(createdAt: Date(timeIntervalSinceReferenceDate: 815_000_000.123))`, fetch it, and `#expect(fetched == highlight)` fails.
- **Fix direction:** round dates to whole milliseconds at the clock (`SystemNow`) or in record initializers, and document it in ADR-0012. Alternatively, use a custom strategy that stores `timeIntervalSinceReferenceDate + 978307200` consistently.
- **Owner:** data-layer.

### L5. FTS update triggers re-index on every `UPDATE`, even when no indexed column changed
- **Severity:** low (performance and churn). GRDB's `__document_fts_au` is `AFTER UPDATE ON document`, not `AFTER UPDATE OF title, author` (`GRDB/FTS/FTS5.swift:272-275`). Phase 1 saves `pdfPosition`, `textPosition`, `progress` and `lastOpenedAt` while reading. Each save deletes and reinserts the title and author postings and grows FTS segments. The same applies to highlight color changes (`highlight_fts`).
- **Location:** `StudyReader/Core/Database/SchemaV1.swift:150-169`.
- **Reproduction:** `UPDATE document SET progress = 0.5 WHERE id = ?` fires `__document_fts_au`. The trigger has no column filter, so it issues a `'delete'` plus an insert into `document_fts` for an unchanged title and author. You can see this with `db.trace` in a test.
- **Fix direction:** if M3 recreates the FTS tables in `v2`, use hand-written triggers restricted with `UPDATE OF <indexed columns>` (an ARCHITECTURE §4 amendment). Otherwise accept the churn and debounce position writes in Phase 1.
- **Owner:** architect, then data-layer.

### L6. `CardState` clashes with `FSRS.CardState`, and `Anchor` clashes with `SwiftUI.Anchor`. Test files that import both modules won't compile.
- **Severity:** low (compile-time only). ADR-0012 renamed types specifically to avoid FSRS, SwiftUI and Testing clashes, but missed these two. The test target already imports FSRS and StudyReader together (`StudyReaderTests/AppTests/PackageLinkTests.swift:4-5`). Phase 2 review-engine tests will do the same and use `CardState`. Renaming later touches records, specs and tests.
- **Location:** `StudyReader/Core/Models/ModelEnums.swift:41` (`CardState`; swift-fsrs also exports `public enum CardState`), `StudyReader/Core/Models/Anchor.swift:53` (`Anchor`; SwiftUI exports `Anchor<Value>`).
- **Reproduction:** confirmed with `swiftc`. Two modules each export `CardState`, and a file importing both gets "error: 'CardState' is ambiguous for type lookup in this context". App files compile only because current-module declarations shadow imported ones.
- **Fix direction:** rename to `ReviewCardState` and `HighlightAnchor` (ADR-0012 table update) before Phase 1 depends on them, or require module-qualified use in the ADR.
- **Owner:** architect (naming), then data-layer.

### L7. Tests and the test host leak temporary libraries, including open SQLite files
- **Severity:** low (hygiene). The container `tmp` currently holds 24 `StudyReader-InMemory/<UUID>` and 90 `StudyReaderTests/<UUID>` folders. Each full run adds 3 and 6. The leaks come from:
  - the host launch;
  - `RootModelTests`;
  - `AppLaunchModelTests.startBecomesReady`;
  - `DatabaseMigrationTests.reopeningDoesNotRemigrate` and `onDiskDatabaseUsesWAL` (which also leave `.sqlite/-wal/-shm`);
  - four `FileStoreTests`.
- **Location:** `StudyReader/App/AppEnvironment.swift:33-42` (`inMemory()` has no cleanup), `StudyReaderTests/AppTests/RootModelTests.swift:8`, `StudyReaderTests/AppTests/AppLaunchModelTests.swift:14`, `StudyReaderTests/CoreTests/DatabaseMigrationTests.swift:73,93`, `StudyReaderTests/CoreTests/FileStoreTests.swift:45,59,73,89`.
- **Reproduction:** `ls ~/Library/Containers/com.ryanvafaei.StudyReader/Data/tmp/StudyReaderTests | wc -l` before and after `./scripts/test.sh`. The count goes up by 6.
- **Fix direction:** give `TestFileStore` a scoped helper (`withTemporaryStore { … }`, or a Swift Testing trait) that removes `<UUID>/`. Let `inMemory()` clear `StudyReader-InMemory/` entries older than the current launch.
- **Owner:** data-layer.

---

## Checked and found OK
- Strict concurrency: `AppDatabase`, `FileStore`, `AppEnvironment` and the repositories are `Sendable`. UI models are `@MainActor`. `FixedNow` uses `Mutex`. No `@unchecked Sendable` and no warnings.
- Dates are stored as `real` and IDs as `text`. Enums are stored as raw values, and `HighlightColor` as an integer. JSON columns are text, and Anchor's JSON shape matches ADR-0012.
- FK cascades fire the FTS delete triggers (tests prove it for highlight, documentText and documentNote). `foreign_keys` is on, `eraseDatabaseOnSchemaChange` is unused, and WAL is enabled on disk.
- `Package.resolved` is tracked despite the `*.xcworkspace/` ignore rule (the negation works). GRDB is pinned to 7.11.1.
