---
name: project-conventions
description: Naming, data-layer, build, and DI conventions decided in Phase 0 planning (ADR-0011/0012) that every later phase spec must reuse
metadata:
  type: project
---

Decided 2026-10-23 while planning Phase 0. Authoritative text: docs/decisions/0011-*.md and 0012-*.md; module map in docs/tasks/phase-0/README.md.

- Record type names avoid module collisions: `LibraryDocument` (table document; clashes Markdown.Document), `DocumentCategory` (ObjectiveC.Category), `LibraryTag` (Testing.Tag), `ReviewLogEntry` (FSRS.ReviewLog). Others = table name in UpperCamel. `Anchor` kept (shadows SwiftUI.Anchor in-app; tests must not import SwiftUI with it).
- Records conform to `StudyRecord` (Unix-second dates). IDs are String UUIDs (GRDB stores UUID as blob). Column enums are raw-value + DatabaseValueConvertible. `CoverSource.automatic = "default"`, `ReaderViewKind` = highlight.view.
- `Anchor` JSON = `{"type":"<case>","<case>":{...}}`. ExportOptions/ThemedReviewFilter decode missing keys as defaults.
- `reviewCard.fsrsCard` / `reviewLog.fsrsLog` are String JSON in records; review-engine owns FSRS conversion (Phase 2). `exportTarget.lastStatus` is a String; E1.8 defines values.
- Built-in category IDs fixed `00000000-0000-0000-0000-00000000000{1..5}` via `BuiltinCategory` (lectureSlides…other). "Other" is the reassignment target on category delete.
- AppDatabase wraps `any DatabaseWriter` (pool on disk, queue in memory). Never REPLACE on FTS-synced tables; never VACUUM without FTS rebuild.
- Upsert rule (ADR-0012 amended 2026-10-24, bug H1): never bare `upsert(db)`; only `upsertAndFetch(db, onConflict: [PK cols])`. Dedupe by fileHash/tag name/category name = explicit lookup then insert. Phase 1 import/tag-create specs must say this. Guard: UpsertConventionTests (T12).
- v1 migration has shipped to the user's real library (2026-10-24): any schema change needs `v2`, never edit SchemaV1.
- DI: `AppEnvironment` (Sendable struct) passed through initializers (RootModel(environment:)), no EnvironmentValues entry. Add new services/repos to it.
- Hosted tests: app uses in-memory env when XCTest env vars present; tests never call `AppEnvironment.live()`.
- Build: ad-hoc signing, no team in Phase 0–1; keychain-access-groups + DEVELOPMENT_TEAM must be added by the E1.8 Google sign-in task. Debug DEAD_CODE_STRIPPING=NO; packages only on app target. Default actor isolation nonisolated.
- Test layout: StudyReaderTests/{AppTests,CoreTests,SupportTests,Support,Fixtures}; feature tests go in `<Feature>Tests/`. Fixtures loaded via Bundle(for:) subdirectory "Fixtures/<kind>".
- Fixture constants (PDFFixtureBuilder.headerText, richRunsText, hyphenatedLines, slideBulletLines, coloredRect; MarkdownFixtures names all-elements/front-matter/rich-inline/persian) are interfaces later tests rely on.

**Why:** these were chosen to keep Haiku implementers from hitting name ambiguity and GRDB default pitfalls.
**How to apply:** use these exact names in Phase 1+ specs; extend `DocumentRepository`, `FileStore`, `AppEnvironment` rather than creating parallel types. Related: [[phase-status]].
