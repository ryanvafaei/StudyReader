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

T09 and T10 only need T01; they're last so the database chain isn't interrupted, but they may run any time after T01 if a database task is blocked.

## Module map after Phase 0

```
StudyReader/App/                 StudyReaderApp, RootView, RootModel, SidebarItem, AppEnvironment, AppLaunchModel, LaunchView
StudyReader/Core/Support/        Now, SystemNow, Log
StudyReader/Core/Files/          FileStore, FileStoreError
StudyReader/Core/Models/         ModelEnums, Anchor (+PDF/Text/ImageAnchor, CGRectCodable), ColumnValues,
                                 StudyRecord, DocumentCategory, LibraryDocument, DocumentText, Highlight,
                                 LibraryTag, HighlightTag, DocumentTag, DocumentNote, ReviewCard, ReviewLogEntry,
                                 ThemedReview, ExportTarget, HighlightEmbedding
StudyReader/Core/Database/       AppDatabase, SchemaV1, BuiltinCategory
StudyReader/Core/Repositories/   CategoryRepository, DocumentRepository
StudyReader/Resources/           Info.plist + StudyReader.entitlements (generated), Localizable.xcstrings, Assets.xcassets
StudyReaderTests/Support/        FixedNow, TestFileStore, TestData, PDFFixtureBuilder, MarkdownFixtures
StudyReaderTests/Fixtures/       markdown/*.md  (folder reference; private/ is git-ignored)
StudyReaderTests/AppTests/, CoreTests/, SupportTests/
```

## Notes for the orchestrator
- Build/test commands are in CLAUDE.md. Swift Testing identifiers for `-only-testing:` are `StudyReaderTests/<Suite>/<test>()`; if the trailing `()` form doesn't match, try without it.
- T01 needs network access for package resolution on the first build, and `xcodegen` installed (`brew install xcodegen`).
- T01 and T08 need a user visual check (steps are in each spec). Other tasks are verified by tests only.
- Test names in each spec are the acceptance contract; reviewers check that each named test exists and asserts the stated behaviour.
- Phase 0 has no SPEC feature ACs of its own. It prepares fixtures and types named by F-02, F-03, F-05, F-06, F-07, F-08, F-11, F-12 ACs in Phase 1.

## Phase done when
- All 10 tasks are approved and committed (`TNN: <title>`).
- Full test suite passes via test-runner; the app launches and creates its database in the sandbox container.
- bug-hunter has run and its critical/high findings are fixed.

## Queued fixes

None. The bundle version fix shipped as T11.
