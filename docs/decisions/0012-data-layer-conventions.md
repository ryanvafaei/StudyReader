# ADR-0012: Data-layer naming and coding conventions

- Status: Accepted (amended 2026-10-24: upsert rule from bug hunt `docs/bugs/phase-0.md` H1; value-type renames (L6), storage-rounded dates (L4), canonical IDs (L1), FTS triggers (ADR-0013))
- Date: 2026-10-23

## Context
ARCHITECTURE §4 defines the SQL schema but not the Swift record types. Several obvious names collide with imported modules (`Markdown.Document`, `Testing.Tag`, `FSRS.ReviewLog`, `FSRS.CardState`, `ObjectiveC.Category`, `SwiftUI.Anchor`). GRDB defaults (UUID stored as a blob, Date stored as text, REPLACE semantics) don't match the schema.

## Decision
- Record type per table: `category`→`DocumentCategory`, `document`→`LibraryDocument`, `documentText`→`DocumentText`, `highlight`→`Highlight`, `tag`→`LibraryTag`, `highlightTag`→`HighlightTag`, `documentTag`→`DocumentTag`, `documentNote`→`DocumentNote`, `reviewCard`→`ReviewCard`, `reviewLog`→`ReviewLogEntry`, `themedReview`→`ThemedReview`, `exportTarget`→`ExportTarget`, `highlightEmbedding`→`HighlightEmbedding`. Each record sets `databaseTableName` explicitly. Property names equal column names.
- Column value types that would clash: `highlight.anchor` is `HighlightAnchor` (was `Anchor`, which clashes with `SwiftUI.Anchor`), and `reviewCard.state` is `ReviewCardState` (was `CardState`, which clashes with `FSRS.CardState`). Only the Swift names changed. SQL values and JSON are unchanged. `NameClashTests` (T13) compiles every record and value type with SwiftUI, FSRS, Markdown, GRDB and Testing imported.
- All records conform to `StudyRecord` (Codable, Sendable, FetchableRecord, PersistableRecord), which stores dates as Unix seconds (`.timeIntervalSince1970`).
- **Dates:** a `Date` survives the Unix-seconds round trip exactly only if it lies on a 1/1024 s grid. `Date.storageRounded` rounds down to that grid. `SystemNow` returns storage-rounded dates, so any record built from `Now` is `==` to its fetched copy. Any other date written to a record (for example FSRS-computed due dates in Phase 2) must go through `.storageRounded` before it is saved. Tests may keep using whole-second dates.
- IDs are `String` (`UUID().uuidString`, canonical uppercase), never `UUID` (GRDB would store a 16-byte blob). `FileStore` rejects non-canonical IDs, so lowercase UUID strings must never be created in app code.
- Column enums are `String`/`Int` raw-value enums conforming to `DatabaseValueConvertible`.
- JSON columns are Codable value types (Core/Models/ColumnValues.swift, Anchor.swift). `HighlightAnchor` encodes as `{"type": "<case>", "<case>": {...}}`. Option and filter types decode missing keys as defaults.
- `reviewCard.fsrsCard` and `reviewLog.fsrsLog` are `String` (JSON) in records. review-engine owns FSRS encoding (Phase 2).
- Built-in categories have fixed IDs `00000000-0000-0000-0000-00000000000{1…5}` (`BuiltinCategory`).
- `AppDatabase` wraps `any DatabaseWriter`: a `DatabasePool` on disk, a `DatabaseQueue` in memory (a pool can't be in-memory).
- FTS5 tables are external-content tables. v1 kept them in sync with GRDB `synchronize(withTable:)` triggers. From v2 they use hand-written triggers with `AFTER UPDATE OF <indexed columns>` and the `studyreader` tokenizer (ADR-0013, ADR-0014). Never use `REPLACE` conflict resolution on `document`, `documentText`, `highlight` or `documentNote`, because delete triggers don't fire (guard: `RecordConventionTests`). Never `VACUUM` without an FTS `'rebuild'` afterwards, because non-aliased rowids may change.
- Writes: use `insert` for new rows (it throws `DatabaseError` on any UNIQUE conflict). Use `update` or `save` for existing rows (both match by primary key only). Upsert only with the conflict target set to the primary key: `try record.upsertAndFetch(db, onConflict: ["id"])`. Composite keys list their PK columns, e.g. `["documentId", "unitIndex"]`. Never call `upsert(db)`, and never call `upsertAndFetch` without `onConflict:`, on any table.
  - Why: GRDB's default upsert emits `ON CONFLICT DO UPDATE` with no target, so it fires on *every* uniqueness constraint. A secondary conflict (`document.fileHash`, or the case-insensitive `category.name` and `tag.name`) silently overwrites the *other* row's non-key columns (title, `storedPath`, `addedAt`, …). The new id never exists, and no error is raised. With a PK target, a secondary conflict throws instead.
- Dedupe by a secondary unique column (import by `fileHash`, create a tag or category by name) is an explicit lookup first (`filter(Column("fileHash") == hash).fetchOne`), then `insert` or reuse. Never an upsert.
- Never use `eraseDatabaseOnSchemaChange`.

## Alternatives considered
Plain names with module qualification at every use site; a `Record` suffix on every type; GRDB defaults for UUID and Date; storing `timeIntervalSinceReferenceDate` (exact, but not Unix seconds as ARCHITECTURE §4 specifies); rounding to whole milliseconds (not exact through the 1970 offset).

## Consequences
Later phases use these names in specs. `UpsertConventionTests` (T12) guards the upsert rule, and reviewers reject any `upsert(` call and any `upsertAndFetch(` call without a target. `DateStorageTests` (T21) guards the date rule.
