---
name: data-layer
description: Implements database and model tasks - GRDB schema, migrations, FTS5 search tables, repositories for documents, highlights, notes, tags, categories, cards, export targets, embeddings; test fixtures. Use for tasks assigned to data-layer in docs/tasks/.
tools: Read, Edit, Write, Bash, Grep, Glob
model: haiku
effort: medium
memory: project
skills:
  - implementation-rules
autoCompactWindow: 100000
color: blue
---

You implement data-layer tasks for StudyReader. Follow the preloaded implementation-rules skill exactly.

## Domain rules
- The schema is defined in `docs/ARCHITECTURE.md` §4. Use those table and column names exactly. Code lives in `StudyReader/Core/Database/`, `Core/Models/`, `Core/Repositories/`.
- GRDB `DatabasePool` (WAL) in `AppDatabase`; `AppDatabase.makeInMemory()` for tests.
- Migrations follow ADR-0013: a migration is frozen once its task is committed; fixes go into a new migration with a schema golden (`Fixtures/schema/vN.sql`, copied from test output, never hand-edited) and an upgrade test from `V1FixtureDatabase`. A failing frozen-schema test means revert your edit, not update the golden.
- Records are `Codable`, `FetchableRecord`, `PersistableRecord` structs following ADR-0012 (type names `LibraryDocument`, `DocumentCategory`, `LibraryTag`, `ReviewLogEntry`, `ReviewCardState`, `HighlightAnchor`; no REPLACE conflict policy, no `INSERT OR REPLACE`). JSON columns hold `Codable` types (e.g. `HighlightAnchor`, filters).
- FTS5 tables (`documentText_fts`, `highlight_fts`, `documentNote_fts`, `document_fts`) are external-content tables. From v2 on (ADR-0013, ADR-0014) they use hand-written `_ai`/`_ad`/`_au` triggers, with the update trigger `AFTER UPDATE OF <indexed columns>`, and the tokenizer ADR-0014 specifies. Never use `synchronize(withTable:)`.
- Frequent non-text saves (reading position, progress, `lastOpenedAt`, color, status) use `update(db, columns:)` or `updateChanges(db, from:)` so they don't re-index.
- Repositories are `Sendable` structs with `async` methods; expose `ValueObservation`s for lists the UI shows live.
- Deleting a document cascades in SQL; the repository then asks `FileStore` to delete the document folder.
- Multi-row changes run in one transaction.
- Test fixtures (Phase 0): `PDFFixtureBuilder` per ARCHITECTURE §15 generates PDFs with Core Text; no binary fixtures unless the spec allows.
