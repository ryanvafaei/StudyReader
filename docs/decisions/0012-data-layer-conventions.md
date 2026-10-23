# ADR-0012: Data-layer naming and coding conventions

- Status: Accepted (amended 2026-10-24: upsert rule, from bug hunt `docs/bugs/phase-0.md` H1)
- Date: 2026-10-23

## Context
ARCHITECTURE §4 defines the SQL schema but not the Swift record types. Several obvious names collide with imported modules (`Markdown.Document`, `Testing.Tag`, `FSRS.ReviewLog`, `ObjectiveC.Category`), and GRDB defaults (UUID as blob, Date as text, REPLACE semantics) don't match the schema.

## Decision
- Record type per table: `category`→`DocumentCategory`, `document`→`LibraryDocument`, `documentText`→`DocumentText`, `highlight`→`Highlight`, `tag`→`LibraryTag`, `highlightTag`→`HighlightTag`, `documentTag`→`DocumentTag`, `documentNote`→`DocumentNote`, `reviewCard`→`ReviewCard`, `reviewLog`→`ReviewLogEntry`, `themedReview`→`ThemedReview`, `exportTarget`→`ExportTarget`, `highlightEmbedding`→`HighlightEmbedding`. Each sets `databaseTableName` explicitly. Property names equal column names.
- All records conform to `StudyRecord` (Codable, Sendable, FetchableRecord, PersistableRecord) which stores dates as Unix seconds (`.timeIntervalSince1970`).
- IDs are `String` (`UUID().uuidString`), never `UUID` (GRDB would store a 16-byte blob).
- Column enums are `String`/`Int` raw-value enums conforming to `DatabaseValueConvertible`.
- JSON columns are Codable value types (Core/Models/ColumnValues.swift, Anchor.swift). `Anchor` encodes as `{"type": "<case>", "<case>": {...}}`. Option/filter types decode missing keys as defaults.
- `reviewCard.fsrsCard` and `reviewLog.fsrsLog` are `String` (JSON) in records; review-engine owns FSRS encoding (Phase 2).
- Built-in categories have fixed IDs `00000000-0000-0000-0000-00000000000{1…5}` (`BuiltinCategory`).
- `AppDatabase` wraps `any DatabaseWriter`: `DatabasePool` on disk, `DatabaseQueue` in memory (a pool can't be in-memory).
- FTS5 tables use GRDB `synchronize(withTable:)` triggers. Never use `REPLACE` conflict resolution on `document`, `documentText`, `highlight`, `documentNote` (delete triggers don't fire). Never `VACUUM` without an FTS `'rebuild'` afterwards (non-aliased rowids may change).
- Writes: `insert` for new rows (throws `DatabaseError` on any UNIQUE conflict), `update`/`save` for existing rows (both match by primary key only). Upsert only with the conflict target set to the primary key: `try record.upsertAndFetch(db, onConflict: ["id"])` (composite keys list their PK columns, e.g. `["documentId", "unitIndex"]`). Never call `upsert(db)`, or `upsertAndFetch` without `onConflict:`, on any table. Why: GRDB's default upsert emits `ON CONFLICT DO UPDATE` with no target, so it fires on *every* uniqueness constraint. A secondary conflict (`document.fileHash`, and the case-insensitive `category.name`, `tag.name`) silently overwrites the *other* row's non-key columns (title, `storedPath`, `addedAt`, …), the new id never exists, and no error is raised. With a PK target, a secondary conflict throws instead.
- Dedupe by a secondary unique column (import by `fileHash`, create tag/category by name) is an explicit lookup first (`filter(Column("fileHash") == hash).fetchOne`), then `insert` or reuse; never an upsert.
- Never use `eraseDatabaseOnSchemaChange`.

## Alternatives considered
Plain names with module qualification at every use site; `Record` suffix on every type; GRDB defaults for UUID/Date.

## Consequences
Later phases use these names in specs. Dates round-trip through `Double`, so tests use whole-second dates. `UpsertConventionTests` (T12) guards the upsert rule; reviewers reject any `upsert(` or target-less `upsertAndFetch(` call.
