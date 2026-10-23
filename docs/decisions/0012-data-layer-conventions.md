# ADR-0012: Data-layer naming and coding conventions

- Status: Accepted
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
- FTS5 tables use GRDB `synchronize(withTable:)` triggers. Never use `REPLACE` conflict resolution on `document`, `documentText`, `highlight`, `documentNote` (delete triggers don't fire); use `update`/`upsert`/`save`. Never `VACUUM` without an FTS `'rebuild'` afterwards (non-aliased rowids may change).
- Never use `eraseDatabaseOnSchemaChange`.

## Alternatives considered
Plain names with module qualification at every use site; `Record` suffix on every type; GRDB defaults for UUID/Date.

## Consequences
Later phases use these names in specs. Dates round-trip through `Double`, so tests use whole-second dates.
