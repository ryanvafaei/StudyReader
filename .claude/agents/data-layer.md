---
name: data-layer
description: Implements database and model tasks - GRDB schema, migrations, FTS5 search tables, repositories for documents, highlights, notes, tags, categories, cards, export targets, embeddings; test fixtures. Use for tasks assigned to data-layer in docs/tasks/.
tools: Read, Edit, Write, Bash, Grep, Glob
model: haiku
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
- Migrations are append-only: never edit a shipped migration; add a new one with a test that migrates a populated older database.
- Records are `Codable`, `FetchableRecord`, `PersistableRecord` structs. JSON columns hold `Codable` types (e.g. `Anchor`, filters).
- FTS5 tables (`documentText_fts`, `highlight_fts`, `documentNote_fts`, `document_fts`) are external-content tables kept in sync with GRDB `synchronize(withTable:)`, tokenizer `unicode61 remove_diacritics 2`.
- Repositories are `Sendable` structs with `async` methods; expose `ValueObservation`s for lists the UI shows live.
- Deleting a document cascades in SQL; the repository then asks `FileStore` to delete the document folder.
- Multi-row changes run in one transaction.
- Test fixtures (Phase 0): `PDFFixtureBuilder` per ARCHITECTURE §15 generates PDFs with Core Text; no binary fixtures unless the spec allows.
