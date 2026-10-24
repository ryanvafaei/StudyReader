---
name: project-conventions
description: Naming, data-layer, migration, search, build and DI conventions (ADR-0011..0014) that every later phase spec must reuse
metadata:
  type: project
---

Decided 2026-10-23/24 in Phase 0 planning and bug-hunt fixes. Authoritative text: docs/decisions/0011–0014; module map in docs/tasks/phase-0/README.md.

- Record names avoid module clashes: `LibraryDocument`, `DocumentCategory`, `LibraryTag`, `ReviewLogEntry`; others = table name UpperCamel. Value types renamed in T13: `HighlightAnchor` (was Anchor; file still Anchor.swift), `ReviewCardState` (was CardState). JSON/SQL unchanged. Guard: NameClashTests.
- Records conform to `StudyRecord` (Unix-second REAL dates). Dates must be `.storageRounded` (1/1024 s grid) to be == after fetch; `SystemNow` rounds (T21). Phase 2 FSRS due dates must apply `.storageRounded`.
- IDs: canonical uppercase `UUID().uuidString`; FileStore rejects others, builders throw, `url(forRelativePath:)` returns nil on escape (T20).
- `HighlightAnchor` JSON = `{"type":"<case>","<case>":{...}}`. ExportOptions/ThemedReviewFilter decode missing keys as defaults.
- Upsert: only `upsertAndFetch(db, onConflict: [PK cols])`; dedupe by fileHash/name = lookup then insert. Never REPLACE (RecordConventionTests). Never VACUUM without FTS rebuild.
- Migrations (ADR-0013): frozen once the task is committed; v1 and v2 frozen; next schema change = `v3` + golden `Fixtures/schema/v3.sql` (from test output) + upgrade test from `V1FixtureDatabase`. `SchemaSnapshotTests/registeredMigrationsInOrder` must be extended.
- FTS (v2+): tokenizer `studyreader` (`SearchTokenizer` wrapper over unicode61 + `SearchTokenNormalizer`), registered in `AppDatabase.makeConfiguration()` prepareDatabase. Hand-written triggers `<fts>_ai/_ad/_au` with `AFTER UPDATE OF <indexed cols>`; never `synchronize(withTable:)`. Normalizer change = new migration + rebuild. SearchQueryParser does no normalization.
- Phase 1 position/progress/lastOpenedAt/color saves must use `update(db, columns:)` or `updateChanges` (full `update(db)` fires FTS triggers).
- Every test writing indexed tables ends with `FTSIntegrity.check(db)`. Temp stores: `defer { TestFileStore.remove(store) }`.
- Errors: opening the library throws `AppDatabaseError`; UI shows only its texts or a generic message, never raw DatabaseError.
- DI: `AppEnvironment` (Sendable struct) through initializers. In-memory env when XCTest env vars or `-StudyReaderInMemory`; tests never call `live()`. `AppLaunchModel.start()` is async (detached factory).
- Build: ad-hoc signing until E1.8 adds keychain-access-groups + DEVELOPMENT_TEAM. Debug DEAD_CODE_STRIPPING=NO; packages only on app target; default isolation nonisolated.
- Test layout: StudyReaderTests/{AppTests,CoreTests,SupportTests,Support,Fixtures}; feature tests in `<Feature>Tests/`. Fixtures via Bundle(for:) subdirectory "Fixtures/<kind>". test.sh filters use struct names, not @Suite display names.
- Shared test interfaces: PDFFixtureBuilder constants, MarkdownFixtures names, `ArabicScriptSamples` (Persian/Arabic strings as \u escapes), `V1FixtureDatabase` IDs.

**Why:** chosen to keep Haiku implementers away from name ambiguity, GRDB default pitfalls and silent schema drift on the user's real library.
**How to apply:** use these exact names and rules in Phase 1+ specs; extend `DocumentRepository`, `FileStore`, `AppEnvironment` rather than creating parallel types. Related: [[phase-status]].
