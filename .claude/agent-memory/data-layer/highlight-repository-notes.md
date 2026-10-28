---
name: highlight-repository-notes
description: T35 HighlightRepository pitfalls: FTSIntegrity must run in write, snapshot file cleanup, color enum cases
metadata:
  type: project
---

HighlightRepository lives at `StudyReader/Core/Repositories/HighlightRepository.swift`; tests at `StudyReaderTests/CoreTests/HighlightRepositoryTests.swift` (6 tests, passing). AppEnvironment exposes `highlightRepository`.

- `FTSIntegrity.check` writes (`integrity-check` insert). Calling it inside `writer.read` fails with "attempt to write a readonly database". Always wrap it in `writer.write`.
- `HighlightColor` has only yellow, green, blue, pink, purple. There is no `.red`.
- Column-limited saves: `updateColor` and `updateNote` / `updateAnchor` pass explicit `columns:` to `update(db, columns:)`. Keep `text`, `editedText`, `note` out of color/anchor updates so `highlight_fts_au` does not re-index.
- Snapshot cleanup: `delete` removes the DB row first, then `fileStore.url(forRelativePath: imagePath)`, skipping missing files. Test ids must be canonical uppercase UUID strings.

- Review round 2: `updates` uses distinct `updatedAt` per call (referenceDate +60/+120/+180) and fetches after each step. The FTS check compares `highlight_fts` MATCH rowids with `SELECT rowid FROM highlight`. Ordering test covers positionKey, createdAt and id tie-breaks.

- T78 (highlight/tag/export queries): `HighlightBrowseSQL.items(db, filter:, sort:, onlyIds:)` is the shared browse query. Call it inside one `writer.read` (or inside `ValueObservation.tracking`) and do not reintroduce a separate browse read. `HighlightRepository.writer` is private again. Batched tag names come from `TagRepository.tagNamesByHighlight(inDocument:)`, one query, not per-highlight lookups. `ExportRepository` reads each export in a single `writer.read`.

**Why:** Hit both pitfalls while writing T35 tests. T78 consolidated the browse and export reads.
**How to apply:** Check these before writing tests that call FTSIntegrity or use HighlightColor.
