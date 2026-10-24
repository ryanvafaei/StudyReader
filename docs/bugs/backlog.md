# Bug backlog

Policy (user decision 2026-10-24): from now on, bug hunts get fix tasks only for critical/high findings and for mediums that get more expensive later; the rest are listed here.

"More expensive later" means the fix cost grows with use or with later work, for example anything that needs a schema migration, rewrites stored data, or changes an interface many later tasks will build on. Every other medium and every low finding goes into this file instead of becoming a task.

Each entry: finding ID and title, severity, link to the bug report section, one line on why it was deferred. Remove an entry when a task fixes it, and name that task.

## Phase 0

None. All Phase 0 findings (H1, M1–M5, L1–L7 in [`phase-0.md`](phase-0.md)) were planned as fix tasks T12–T23 before this policy existed. M3 was narrowed to English-only search (ADR-0014); its Persian/Arabic cases were dropped deliberately, not deferred.

## T22 review

- **T22-R1. System SQLite logging can include SQL and the database path.** Severity: low. Source: the T22 code review ([T22 spec](../tasks/phase-0/T22-app-database-error.md)). On open or migration failures, the OS SQLite library prints `[logging]` lines that can contain the failing SQL and the library file's path. This output comes from the OS, not our logger, so our no-PII logging rule (ARCHITECTURE §14) can't control it. Deferred: it only reaches the local console and unified log, the UI never shows it (T23), and no task is planned.

## T27 follow-up

- **T27-F1. Check that a normal launch doesn't pick the in-memory library, and whether Xcode Previews are guarded.** Severity: low. Source: [T27 spec](../tasks/phase-0/T27-test-host-guard-before-live-open.md). Verify once in Console that a normal launch (Xcode Run / Finder) does not log "Using the in-memory library" (subsystem app category, `Log.app` in `AppLaunchModel.swift`). Xcode Previews are not guarded (unverified whether they run `live()`). Deferred: the T27 tests cover only the test host, and both checks are manual (a Console run, a Preview run); no task is planned.
  - Revisit when: before Phase 1 import work.

## Phase 0 second pass

Source: [`phase-0-second-pass.md`](phase-0-second-pass.md) (2026-10-24). Its only medium, M1, was fixed by T26. By user decision on 2026-10-24, L1 was fixed by T27 and the `DateStorageTests` part of L7 by T26; both are committed and removed here. The other lows have no tasks. Plan each one as a task when its "revisit when" trigger is reached, then remove it here and name the task.

- **L2. `inMemory(now:)` uses the injected clock for temp-folder cleanup.** Severity: low. [Report](phase-0-second-pass.md#l2-inmemorynow-uses-the-injected-domain-clock-to-judge-folder-age-so-a-future-fixednow-deletes-the-folders-of-tests-that-are-still-running). A future `FixedNow` makes every existing `StudyReader-InMemory/<UUID>` folder look stale, so parallel tests lose their folders.
  - Suggested fix: compute the one-hour cleanup cutoff from the real wall clock or the folders' file-system dates, independent of the injected `Now`, or clean up only in `defaultFactory`. Add the report's failing test.
  - Suggested agent: ui-builder.
  - Revisit when: opportunistic. At the latest before any test passes a future `FixedNow` to `AppEnvironment.inMemory(now:)` (Phase 2 scheduling tests).
- **L3. A soft hyphen at a line end isn't joined, so `photo­\nsynthesis` isn't found as `photosynthesis`.** Severity: low. [Report](phase-0-second-pass.md#l3-soft-hyphens-at-a-line-end-arent-joined-so-the-main-pdf-case-that-adr-0014-targets-still-misses). The tokenizer handles U+00AD only inside a token, and ARCHITECTURE §6 rule 5 only joins lines ending in `-`.
  - Suggested fix: amend ARCHITECTURE §6 rule 5 so a line ending in U+00AD (or U+2010) is joined like `-`. Extraction is versioned, so no migration. Test with `SearchSamples` line-end variants, and check a Word-exported lecture PDF in `Fixtures/private/`.
  - Suggested agent: architect (§6 amendment), then pdf-engine (extraction).
  - Revisit when: PDF text extraction is planned (Phase 1). Put the rule into the extraction task's spec, not a separate fix.
- **L4. FileStore rejects uppercase extensions, and `relativePath(for:)` returns paths `url(forRelativePath:)` won't resolve.** Severity: low. [Report](phase-0-second-pass.md#l4-filestore-rejects-uppercase-file-extensions-and-relativepathfor-accepts-paths-that-urlforrelativepath-rejects). Passing `pathExtension` from `SLIDES.PDF` throws `.invalidFileExtension("PDF")`, and a stored non-canonical relative path can never be resolved.
  - Suggested fix: derive the stored extension from `fileType` (or lowercase it) and say so in the doc comment. Make `relativePath(for:)` return nil unless the first component is a canonical ID. Add tests for both.
  - Suggested agent: data-layer.
  - Revisit when: import (Phase 1, F-01/F-02) is planned. Do it as the first task of the import epic, before the importer stores any `storedPath`.
- **L5. An older build opens a library migrated by a newer build without error.** Severity: low. [Report](phase-0-second-pass.md#l5-a-newer-library-is-opened-silently-by-an-older-build). GRDB skips applied migrations it doesn't know, so an older build writes against a schema it doesn't understand.
  - Suggested fix: in `AppDatabase.makeShared`, check `migrator.hasBeenSuperseded(db)` and throw a new `AppDatabaseError.newerVersion` with its own user text. Test: insert `'v3'` into `grdb_migrations`, then reopen and expect the throw.
  - Suggested agent: data-layer.
  - Revisit when: before first release. Better: together with the first `v3` migration, since from then on an older build (for example an older commit run during bisecting) can meet a newer library.
- **L6. Disk-full and busy errors get the wrong recovery suggestion.** Severity: low. [Report](phase-0-second-pass.md#l6-disk-full-and-busy-failures-get-the-wrong-recovery-suggestion). SQLITE_FULL/IOERR during migration says "Quit and reopen", and SQLITE_BUSY/LOCKED at open says "check free disk space".
  - Suggested fix: in `AppDatabaseError.wrap`, map FULL and IOERR to a disk-space case at both stages, and map BUSY and LOCKED to a "close other copies of StudyReader" suggestion. Test each mapping with `DatabaseError(resultCode:)`.
  - Suggested agent: data-layer.
  - Revisit when: before first release. If L5 is fixed first, do both in one task, since both add `AppDatabaseError` cases and user texts.
- **L7. Some tests that write FTS-indexed tables don't end with `FTSIntegrity.check`.** Severity: low. [Report](phase-0-second-pass.md#l7-several-tests-that-write-fts-indexed-tables-dont-end-with-ftsintegritycheck-although-architecture-15-says-every-one-does). `UpsertConventionTests`, `ReviewExportRecordTests` and `RecordCodingTests` break the ARCHITECTURE §15 rule. A manual check found the index consistent. (The `DateStorageTests` part was fixed by [T26](../tasks/phase-0/T26-date-query-arguments.md).)
  - Suggested fix: add `try FTSIntegrity.check(db)` at the end of the write closures in those three suites. Don't narrow the ARCHITECTURE sentence.
  - Suggested agent: data-layer.
  - Revisit when: opportunistic, for example the next task that touches one of those test files. Phase 1 specs that write FTS tables must keep requiring the check.
