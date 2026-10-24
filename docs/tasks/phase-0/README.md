# Phase 0 — Bootstrap

Epics (SPEC §6): E0.1 Project, E0.2 Database, E0.3 Fixtures. No user-facing features; the outcome is a project that builds, launches, has the full v1 schema with records and a repository pattern, and has test fixtures for Phase 1.

New ADRs for this phase: [0011 build, signing, hosted tests](../../decisions/0011-build-signing-and-test-hosting.md), [0012 data-layer conventions](../../decisions/0012-data-layer-conventions.md).

## Task order

Run in this order, one at a time (CLAUDE.md workflow).

| # | Task | Agent | Depends on | Visual check |
|---|---|---|---|---|
| 1 | [T01 XcodeGen project, build settings, empty app shell](T01-project-and-app-shell.md) | ui-builder | none | yes |
| 2 | [T02 Core support: clock, logging, FileStore](T02-core-support-and-filestore.md) | data-layer | T01 | no |
| 3 | [T03 Model value types: column enums, Anchor, JSON column values](T03-model-value-types.md) | data-layer | T01 | no |
| 4 | [T04 AppDatabase, migration v1, FTS5, seed categories](T04-appdatabase-schema-v1.md) | data-layer | T02, T03 | no |
| 5 | [T05 Records part 1: categories, documents, highlights, tags, notes](T05-records-library-annotations.md) | data-layer | T04 | no |
| 6 | [T06 Records part 2: review, export, embeddings](T06-records-review-export-embedding.md) | data-layer | T05 | no |
| 7 | [T07 Repository skeleton: Category/Document repositories](T07-repositories-skeleton.md) | data-layer | T05 | no |
| 8 | [T08 AppEnvironment and launch wiring](T08-app-environment-and-launch.md) | ui-builder | T01, T07 | yes |
| 9 | [T09 PDFFixtureBuilder](T09-pdf-fixture-builder.md) | data-layer | T01 | no |
| 10 | [T10 Markdown fixtures and loader](T10-markdown-fixtures.md) | data-layer | T01 | no |
| 11 | [T11 Bundle version from build settings](T11-bundle-version.md) | ui-builder | T01 | no |
| 12 | [T12 Guard tests for primary-key-only upsert](T12-upsert-guard-tests.md) (bug hunt H1) | data-layer | T05, T07 | no |

T09 and T10 only need T01; they're last so the database chain isn't interrupted, but they may run any time after T01 if a database task is blocked.

### Bug-hunt fixes (from `docs/bugs/phase-0.md`, user decisions 2026-10-24)

New ADRs: [0013 frozen migrations, schema goldens, v2](../../decisions/0013-schema-migration-policy-v2.md) and [0014 search tokenizer](../../decisions/0014-search-tokenizer-persian-arabic.md). Amended: ADR-0011 (in-memory launch argument, temp cleanup) and ADR-0012 (renames, dates, canonical IDs, FTS triggers).

| # | Task | Finding | Agent | Depends on | Visual check |
|---|---|---|---|---|---|
| 13 | [T13 Rename `CardState`/`Anchor` to `ReviewCardState`/`HighlightAnchor`](T13-rename-clashing-value-types.md) | L6 | data-layer | T12 | no |
| 14 | [T14 Remove temporary libraries created by tests and the test host](T14-temporary-folder-cleanup.md) | L7 | data-layer | T13 | no |
| 15 | [T15 Guard test-host detection, add `-StudyReaderInMemory`](T15-test-host-detection-guard.md) | M4 | ui-builder | T14 | no |
| 16 | [T16 Schema golden for v1 and populated v1 fixture database](T16-schema-goldens-and-v1-fixture.md) | M1 | data-layer | T14 | no |
| 17 | [T17 FTS integrity helper and REPLACE conflict-policy guard](T17-fts-integrity-and-conflict-guard.md) | M5 | data-layer | T16 | no |
| 18 | [T18 `studyreader` FTS5 tokenizer (ligatures, soft hyphens; English-only)](T18-search-tokenizer.md) | M3 (1/2) | data-layer (model sonnet, effort high) | T17 | no |
| 19 | [T19 Migration v2: FK indexes, tokenizer FTS tables, filtered triggers](T19-migration-v2.md) | M2, M3 (2/2), L5 | data-layer | T16, T17, T18 | no |
| 20 | [T20 FileStore validates IDs, extensions, relative paths](T20-filestore-path-validation.md) | L1 | data-layer | T14 | no |
| 21 | [T21 Storage-rounded dates](T21-storage-rounded-dates.md) | L4 | data-layer | T13 | no |
| 22 | [T22 Typed `AppDatabaseError`](T22-app-database-error.md) | L3 (data) | data-layer | T19 | no |
| 23 | [T23 Async launch off the main actor, safe error messages](T23-async-launch-and-error-message.md) | L2, L3 (UI) | ui-builder | T15, T22 | yes |

Run them in this order, one at a time. The order keeps files that several tasks touch in sequence: `AppEnvironment`/`AppLaunchModel` go T14 → T15 → T23, `AppDatabase.swift` goes T18 → T19 → T22, and `FileStoreTests` goes T14 → T20.

Points of care:
- **T19 changes the user's real library** on the next app launch (v1 → v2). That is the intended upgrade. After T19 is committed, `SchemaV2` is frozen. Any later schema fix needs `v3`.
- T16 and T19 generate golden files from test output (`Fixtures/schema/v1.sql`, `v2.sql`). The implementer reads the `*.actual.sql` path printed by the failing test (under the app container's `tmp`). Goldens are never hand-written or regenerated after commit.
- T18 (a GRDB custom FTS5 tokenizer class under Swift 6) runs as data-layer with model `sonnet` and effort `high` from the first call (user decision 2026-10-24). Treat it as escalated: review it with code-reviewer effort `high`, and if it's rejected twice, stop and ask the user.
- Search is English-only (ADR-0014, user decision 2026-10-24): the tokenizer handles NFKC (ligatures), soft hyphens, case and Latin diacritics. Persian/Arabic folding was deliberately dropped; adding it later needs a new tokenizer version and migration.

## Module map after Phase 0

```
StudyReader/App/                 StudyReaderApp, RootView, RootModel, SidebarItem, AppEnvironment, AppLaunchModel, LaunchView
StudyReader/Core/Support/        Now, SystemNow (storage-rounded), Log
StudyReader/Core/Files/          FileStore (canonical-ID validation), FileStoreError
StudyReader/Core/Models/         ModelEnums (incl. ReviewCardState), Anchor.swift (HighlightAnchor + PDF/Text/ImageAnchor,
                                 CGRectCodable), ColumnValues, StudyRecord (+ Date.storageRounded), DocumentCategory,
                                 LibraryDocument, DocumentText, Highlight, LibraryTag, HighlightTag, DocumentTag,
                                 DocumentNote, ReviewCard, ReviewLogEntry, ThemedReview, ExportTarget, HighlightEmbedding
StudyReader/Core/Database/       AppDatabase, AppDatabaseError, SchemaV1 (frozen), SchemaV2 (frozen after T19),
                                 SearchTokenizer (+ SearchTokenNormalizer), BuiltinCategory
StudyReader/Core/Repositories/   CategoryRepository, DocumentRepository
StudyReader/Resources/           Info.plist + StudyReader.entitlements (generated), Localizable.xcstrings, Assets.xcassets
StudyReaderTests/Support/        FixedNow, TestFileStore (+ remove), TestData, PDFFixtureBuilder, MarkdownFixtures,
                                 SchemaSnapshot, V1FixtureDatabase, FTSIntegrity, SearchSamples
StudyReaderTests/Fixtures/       markdown/*.md, schema/v1.sql, schema/v2.sql  (folder reference; private/ is git-ignored)
StudyReaderTests/AppTests/, CoreTests/, SupportTests/
```

## Notes for the orchestrator
- Build/test commands are in CLAUDE.md. Swift Testing identifiers for `-only-testing:` are `StudyReaderTests/<Suite>/<test>()`; if the trailing `()` form doesn't match, try without it.
- T01 needs network access for package resolution on the first build, and `xcodegen` installed (`brew install xcodegen`).
- T01 and T08 need a user visual check (steps are in each spec). Other tasks are verified by tests only.
- Test names in each spec are the acceptance contract; reviewers check that each named test exists and asserts the stated behaviour.
- Phase 0 has no SPEC feature ACs of its own. It prepares fixtures and types named by F-02, F-03, F-05, F-06, F-07, F-08, F-11, F-12 ACs in Phase 1.

## Phase done when
- All 23 tasks are approved and committed (`TNN: <title>`).
- Full test suite passes via test-runner, and `./scripts/check-fresh-clone.sh` passes. The app launches, and its library is at migration `v2`.
- bug-hunter has run, and its critical/high findings are fixed. Every bug-hunt finding (H1, M1–M5, L1–L7) is covered by T12–T23 (M3 in its narrowed, English-only scope).

## Fix history
- T11 (bundle version) shipped.
- T12 fixes bug hunt H1. ADR-0012 was amended first, so T12 has tests only.
- T13–T23 fix M1–M5 and L1–L7. The user decided on 2026-10-24: a new `v2` migration (v1 stays frozen), fix everything now, and do the L6 renames.
- M3 was narrowed on 2026-10-24 to English-only search (ligatures, soft hyphens). The Persian/Arabic cases in the bug report are intentionally not fixed.
- T22 was re-planned on 2026-10-24 after a BLOCKED report. T18's tokenizer registration made GRDB `fatalError` on a damaged library. Now `prepareDatabase` reads `sqlite_master` before `db.add(tokenizer:)`, so damaged files throw `.damaged`. New tests: `corruptPagesAreReported`, `configurationThrowsOnDamagedFile`.
- Bug-hunt policy from Phase 1 on: see [`docs/bugs/backlog.md`](../../bugs/backlog.md).
