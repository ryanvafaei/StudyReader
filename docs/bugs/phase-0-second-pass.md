# Phase 0 bug hunt, second pass

- Date: 2026-10-24
- Scope: the changes since the first hunt (`abce947..a3719e5`, fix tasks T12–T25). Covered: `SchemaV2.swift`, `SearchTokenizer.swift`, `AppDatabase.swift`, `AppDatabaseError.swift`, `FileStore.swift`, `StudyRecord.swift`/`Now.swift`, `AppEnvironment.swift`, `AppLaunchModel.swift`, `LaunchView.swift`, `MainWindowLayout.swift`, `RootView.swift`, the new test support (`SchemaSnapshot`, `V1FixtureDatabase`, `FTSIntegrity`, `TestFileStore`), ADR-0011–0014 and the ARCHITECTURE/SPEC amendments.
- Baseline: `./scripts/test.sh` gives 154 tests in 30 suites, all passing (run twice, 14:17 and 14:27). No compiler warnings in project code.
- **The user's real library is already at v2.** `grdb_migrations` = `v1, v2`, 0 documents, 0 highlights (checked read-only). The WAL was last written at 13:23:05, after the T19 commit (13:12:56), so v2 ran on a launch during T22. Its schema dump is **byte-identical** to `StudyReaderTests/Fixtures/schema/v2.sql`. Any schema change from now on needs `v3`.
- Test-host isolation holds. Neither test run changed the mtimes of the real `StudyReader.sqlite`, `-wal` or `-shm`. After each run `tmp/StudyReaderTests/` and `tmp/StudyReaderSchema/` are empty, and `tmp/StudyReader-InMemory/` only keeps folders less than one hour old (21, then 17).

Counts: critical 0, high 0, medium 1, low 7.

---

## Medium

### M1. A `Date` used as a query argument is encoded as TEXT, so comparisons with the REAL date columns are silently wrong
- **Severity:** medium. **Costlier later: yes.** This is a convention gap that every date filter in Phases 1–3 builds on. Fixing it now is one ADR rule plus a helper and a guard test. Later it means auditing every query written in the meantime, and some will have shipped wrong results.
- **What happens:** ADR-0012 stores dates as REAL Unix seconds through `StudyRecord.databaseDateEncodingStrategy`. That strategy only applies when a *record* is encoded. A bare `Date` passed as a query argument goes through GRDB's `Date.databaseValue`, which is the TEXT string `"yyyy-MM-dd HH:mm:ss.SSS"`. In SQLite, a REAL value always sorts before a TEXT value. So:
  - `dueAt <= <date>` is true for every row;
  - `dueAt > <date>` is never true;
  - no error is raised.
- **Where it bites:**
  - ARCHITECTURE §10 `DailyReviewBuilder`: "due non-suspended cards (`dueAt ≤ now`)" and the `introducedToday` count.
  - Themed reviews: `lastCompletedAt`.
  - Any Phase 1 "since" filter on `addedAt`, `lastOpenedAt` or `createdAt`.
- **Location:**
  - `StudyReader/Core/Models/StudyRecord.swift:14-21` (record-only strategy).
  - `docs/decisions/0012-data-layer-conventions.md:12-13` (covers storage only, says nothing about query arguments).
  - GRDB: `GRDB/Core/Support/Foundation/Date.swift:46-50` (`databaseValue` is TEXT) and `GRDB/Core/DatabaseValueConvertible.swift:79` (`sqlExpression` = `databaseValue`).
  - Spec that will hit it: `docs/ARCHITECTURE.md:508`.
- **Reproduction:** confirmed with SQLite 3.54.
  ```
  CREATE TABLE reviewCard(id TEXT PRIMARY KEY, dueAt REAL NOT NULL);
  INSERT INTO reviewCard VALUES ('past',1790000000),('future',1900000000);
  SELECT group_concat(id) FROM reviewCard WHERE dueAt <= '2026-10-24 12:00:00.000';  -- past,future
  SELECT count(*)         FROM reviewCard WHERE dueAt >  '2026-10-24 12:00:00.000';  -- 0
  SELECT group_concat(id) FROM reviewCard WHERE dueAt <= 1792843200.0;               -- past
  ```
  The TEXT literal is exactly what `ReviewCard.filter(Column("dueAt") <= now)` binds.
- **Failing test:** `DateStorageTests/dateQueryArgumentsCompareAsUnixSeconds`.
  1. Insert two `ReviewCard`s with `dueAt` = `TestData.referenceDate − 1 day` and `+ 1 day`.
  2. `ReviewCard.filter(Column("dueAt") <= TestData.referenceDate).fetchCount(db)`.
  3. Expected 1. Today it returns 2.
- **Fix direction:**
  - Amend ADR-0012: never bind a `Date` directly; compare with `date.timeIntervalSince1970`, or add a small helper (for example `Date.databaseUnixSeconds`, or a `Column` extension) that every repository uses.
  - Add the test above as a guard.
- **Owner:** architect (ADR-0012 amendment), then data-layer (helper and guard test).

---

## Low

### L1. The test-host guard detects a broken detection only after the host has already opened the real library, and ADR-0011 says the opposite
- **Severity:** low. It's unlikely, since it needs Xcode to change its environment variables. But it is the one Phase 0 safety net for user data. The case that matters: while a `v3` migration is being written, a broken detection would let the test host apply the *uncommitted* `v3` to the user's real library. GRDB never reruns it, which defeats ADR-0013's "frozen at commit".
- **Location:**
  - `docs/decisions/0011-build-signing-and-test-hosting.md:19` ("fails a test instead of opening the real library").
  - Launch path: `StudyReader/App/StudyReaderApp.swift:5,9` → `StudyReader/App/LaunchView.swift:23` → `StudyReader/App/AppLaunchModel.swift:27-32` → `StudyReader/App/AppEnvironment.swift:82-95`.
  - Guard: `StudyReaderTests/AppTests/AppEnvironmentTests.swift:37-40`.
- **Reproduction:** derived from code; I didn't run it, so the user's library was not touched. The test host launches the app first. `LaunchView.task` runs `defaultFactory()`, and with both variables missing it takes `live()` and migrates the real library (you can see each run's own host-created `StudyReader-InMemory/<UUID>` appear at launch, before the tests). Only after that does `hostedProcessIsDetected` run and fail. With detection broken, a run reports one failing test, but the real library has already been opened and migrated.
- **Fix direction:**
  - Add a second, independent signal checked before `live()`, for example a loaded `.xctest` bundle in `Bundle.allBundles` or `NSClassFromString("XCTestCase") != nil`.
  - Reword ADR-0011 to say the test detects the problem; it doesn't prevent it.
- **Owner:** ui-builder (code), architect (ADR wording).

### L2. `inMemory(now:)` uses the injected domain clock to judge folder age, so a future `FixedNow` deletes the folders of tests that are still running
- **Severity:** low (test flakiness, latent). Phase 2 scheduling tests are told to use `FixedNow` (ARCHITECTURE §15), and `inMemory(now:)` is the natural way to inject it.
- **Location:** `StudyReader/App/AppEnvironment.swift:66-67` (`olderThan: now().addingTimeInterval(-3600)`).
- **Failing test:**
  1. `let a = try AppEnvironment.inMemory()`.
  2. `try a.fileStore.createDocumentFolder(documentId: UUID().uuidString)`.
  3. `let b = try AppEnvironment.inMemory(now: FixedNow(Date(timeIntervalSince1970: 1_900_000_000)))`.
  4. `#expect(FileManager.default.fileExists(atPath: a.fileStore.rootURL.path(percentEncoded: false)))` fails. Every folder created before 2030 counts as stale, including folders of parallel tests and the host's own folder.
- **Fix direction:** use the real wall clock (or file system time) for the cleanup cutoff, independent of the injected `Now`. Alternatively, clean up only in `defaultFactory`.
- **Owner:** ui-builder.

### L3. Soft hyphens at a line end aren't joined, so the main PDF case that ADR-0014 targets still misses
- **Severity:** low (search quality, English).
- **What happens:** in a PDF, a soft hyphen only appears where it was drawn, which is at a line break. Extracted text therefore usually has U+00AD followed by a newline or space, not in the middle of a word as in the T18 sample. The tokenizer keeps U+00AD only *inside* a token, and ARCHITECTURE §6 rule 5 only joins lines that end in `-`.
- **Location:** `StudyReader/Core/Database/SearchTokenizer.swift:8,36-42`, `docs/ARCHITECTURE.md:404`. Tests only cover the in-word form: `StudyReaderTests/Support/SearchSamples.swift:4`.
- **Reproduction:** confirmed with `fts5vocab` over `unicode61 remove_diacritics 2 tokenchars '­'`, the wrapped base tokenizer:
  - `photo­synthesis` gives `[photo­synthesis]`, which normalizes to `photosynthesis`.
  - `photo­\nsynthesis` and `photo­ synthesis` give `[photo­, synthesis]`, which normalize to `photo` + `synthesis`. A search for `photosynthesis` returns nothing.
  - Not verified: how often PDFKit returns U+00AD at line ends. Check this with a Word-exported lecture PDF in `Fixtures/private/`.
- **Fix direction:** amend ARCHITECTURE §6 rule 5 so a line ending in U+00AD (or U+2010) is joined like `-` (extraction is versioned, so no migration is needed). Highlight text that crosses a line break keeps the break; decide in Phase 1 whether it needs a tokenizer join (which would mean a rebuild migration).
- **Owner:** architect.

### L4. FileStore rejects uppercase file extensions, and `relativePath(for:)` accepts paths that `url(forRelativePath:)` rejects
- **Severity:** low (API footguns for the Phase 1 importer).
- **Location:** `StudyReader/Core/Files/FileStore.swift:155-163` (only `a`–`z` and `0`–`9`), `:96-103` (`relativePath(for:)` doesn't check the canonical ID), `:82-93`.
- **Reproduction (derived from code):**
  - `originalFileURL(documentId: id, fileExtension: URL(fileURLWithPath: "/x/SLIDES.PDF").pathExtension)` throws `.invalidFileExtension("PDF")`, so passing `pathExtension` straight through fails the import of any `.PDF` file.
  - `relativePath(for: documentsURL/"notes/x.pdf")` returns `"notes/x.pdf"`, but `url(forRelativePath: "notes/x.pdf")` returns nil. A path stored that way can never be resolved again.
- **Fix direction:** derive the stored extension from `fileType` (or lowercase it) and say so in the FileStore doc comment. Make `relativePath(for:)` return nil unless the first component is a canonical ID.
- **Owner:** data-layer.

### L5. A newer library is opened silently by an older build
- **Severity:** low (single developer user, but they build many commits).
- **What happens:** GRDB ignores applied migrations it doesn't know. An older build therefore opens a library migrated by a newer one and writes against a schema it doesn't understand. For example, a pre-T18 build on today's v2 library fails every document or highlight insert with "no such tokenizer: studyreader".
- **Location:** `StudyReader/Core/Database/AppDatabase.swift:11-14,65-74`. GRDB: `Migration/DatabaseMigrator.swift:628-636` (unknown identifiers are skipped, no error).
- **Reproduction (derived from GRDB code):** create a database through `AppDatabase.makeShared`, then `INSERT INTO grdb_migrations VALUES ('v3')`. Reopening with `AppDatabase.makeShared` succeeds with no error.
- **Fix direction:** in `makeShared`, check `migrator.hasBeenSuperseded(db)` (or compare `appliedIdentifiers` with the known ones) and throw a new `AppDatabaseError.newerVersion`.
- **Owner:** data-layer.

### L6. Disk-full and busy failures get the wrong recovery suggestion
- **Severity:** low (error-path UX).
- **What happens:**
  - SQLITE_FULL or SQLITE_IOERR during the migration maps to `.migrationFailed`. Its advice is "Quit and reopen…", which repeats the failure; the v2 `'rebuild'` on a large library is the likely trigger.
  - SQLITE_BUSY or SQLITE_LOCKED at open maps to `.cannotOpen`, which says "Check that your Mac has free disk space".
- **Location:** `StudyReader/Core/Database/AppDatabaseError.swift:21-34,49-58`.
- **Reproduction:** `AppDatabaseError.wrap(DatabaseError(resultCode: .SQLITE_FULL), stage: .migrate)` returns `.migrationFailed(code: 13)`.
- **Fix direction:** map SQLITE_FULL and IOERR to a disk-space case (or `.cannotOpen`) at both stages, and give BUSY or LOCKED a "close other copies of StudyReader" suggestion.
- **Owner:** data-layer.

### L7. Several tests that write FTS-indexed tables don't end with `FTSIntegrity.check`, although ARCHITECTURE §15 says every one does
- **Severity:** low (test coverage). I checked the main gap, the primary-key upsert path that ADR-0012 recommends, in `sqlite3` with the v2 trigger SQL, and it keeps the index consistent. The rule itself is still not enforced.
- **Location:** `docs/ARCHITECTURE.md:566`. The tests without a check:
  - `StudyReaderTests/CoreTests/UpsertConventionTests.swift` (PK upserts on `document`, which fire `document_fts_au`);
  - `DateStorageTests.swift:37-55`;
  - `ReviewExportRecordTests.swift` (highlight inserts and cascade deletes);
  - `RecordCodingTests.swift`.
- **Fix direction:** add the check to those tests, or narrow the ARCHITECTURE sentence to the listed suites.
- **Owner:** data-layer.

---

## First-hunt findings: re-verified

| Finding | Status | Evidence |
|---|---|---|
| H1 untargeted upsert | Fixed | ADR-0012:21-23; `UpsertConventionTests` covers PK upserts and the duplicate `fileHash`/tag-name throws. |
| M1 frozen v1, no fixture | Fixed | `SchemaSnapshotTests` v1 and v2 goldens; `V1FixtureDatabase` (in memory and on disk); `registeredMigrationsInOrder`. The real library's dump matches `v2.sql`. |
| M2 unindexed FK children | Fixed | v2 adds `document_category`, `documentTag_tag`, `reviewLog_card(cardId, reviewedAt)`, `reviewLog_themedReview`. Every FK child column in the schema now has an index or a PK prefix. `foreignKeyLookupsUseIndexes`; a cascade over 2,000 logs passes. |
| M3 tokenizer | Fixed (English scope, ADR-0014) | Ligatures, in-word soft hyphens, case and NFD diacritics are tested on live tables and after the v1 → v2 upgrade. Persian was dropped by user decision. See L3 for the line-end case. |
| M4 test-host detection | Fixed as specified | `hostedProcessIsDetected`, `-StudyReaderInMemory`. See L1 for the "after the fact" gap. |
| M5 FTS desync guards | Fixed | `FTSIntegrity.check`, `replaceDesyncIsDetected`, `RecordConventionTests/noReplaceConflictPolicy`. See L7 for coverage. |
| L1 FileStore traversal | Fixed | Every builder validates IDs; `url(forRelativePath:)` rejects `..`, `.`, empty components, absolute paths and non-canonical first components. See L4. |
| L2 sync launch | Fixed | `start()` is async and runs the factory in `Task.detached`; `factoryRunsOffMainThread`, `concurrentStartsRunFactoryOnce`. |
| L3 raw GRDB error text | Fixed | `AppDatabaseError`; only `errorDescription`/`recoverySuggestion` reach the UI; logs carry the case and code only. A damaged header and corrupt page 1 both give `.damaged`, with no `fatalError`. |
| L4 date round trip | Fixed for `SystemNow` | The 1/1024 s grid is exact through `+978307200` (checked: numerators stay below 2^53). See M1 for the query side. |
| L5 FTS update churn | Fixed | `AFTER UPDATE OF <indexed cols>`; `metadataUpdatesDoNotReindex` traces show trigger statements, so the negative check means something. Full-record `update(db)` still re-indexes, as ADR-0013 documents. |
| L6 name clashes | Fixed | `HighlightAnchor`, `ReviewCardState`; `NameClashTests`. |
| L7 temp leaks | Fixed | 0 leftover `StudyReaderTests/<UUID>` after two runs; in-memory folders older than one hour are removed. |

## Checked and found OK
- v2 trigger SQL, checked in `sqlite3` with unicode61 swapped in:
  - a PK-target upsert (`ON CONFLICT(id) DO UPDATE SET title=…`) fires `document_fts_au`, and `'integrity-check'` passes;
  - metadata-only updates don't fire it.
  - VACUUM on SQLite 3.54 kept the implicit rowids of a TEXT-PK table, and `'integrity-check'` passed afterwards. The ADR-0012 VACUUM rule is conservative, not wrong.
- v2 rolls back as a whole on failure (GRDB runs each migration in a transaction). DROP TRIGGER names match what GRDB 7.11.1 generated for the real library.
- Tokenizer:
  - `normalize` is locale-independent and deterministic (NFKC + `lowercased()`), so 'delete' tokens equal insert tokens.
  - GRDB passes the wrapped tokenizer's offsets through, so `snippet()` shows the original text.
  - It is registered on pool readers. No PII is logged.
- `prepareDatabase` order: the schema read throws before `add(tokenizer:)`. `configurationThrowsOnDamagedFile` and `corruptPagesAreReported` pass.
- Date rounding: `storageRounded` is monotonic, idempotent and exact for past, future and pre-1970 dates.
- Concurrency: the `AppLaunchModel` once-guard holds when `.task` re-runs or is cancelled (the detached task isn't cancelled, and its result still lands). `Result<AppEnvironment, any Error>` is Sendable. No `try!`, `as!` or force unwraps in app code.
- The main file of the real library is 4 KB and the WAL is 362 KB: the app exits without a final checkpoint. That is normal for SQLite and safe. Any future backup feature must copy the folder or use the SQLite backup API, never `StudyReader.sqlite` alone.
- Not verified: whether Xcode Previews of the app target run `StudyReaderApp`'s scene, and with it `live()`. I couldn't check this without running previews.
