---
name: database-schema-v1-notes
description: AppDatabase/SchemaV1 layout, GRDB FTS5 API used, and Swift Testing pitfalls hit while writing T04 tests
metadata:
  type: reference
---

Files: `StudyReader/Core/Database/` holds `AppDatabase.swift` (DatabasePool on disk, DatabaseQueue in memory, `migrator` with "v1"), `SchemaV1.swift` (verbatim ARCHITECTURE §4 SQL, 4 FTS5 tables, builtin category seed), `BuiltinCategory.swift` (fixed UUIDs 00000000-...-00000000000N).

- FTS tokenizer: `t.tokenizer = .unicode61(diacritics: .remove)` compiles on GRDB 7.11. No descriptor fallback needed.
- `Row` is not `Sendable` in GRDB 7.11. Map rows to tuples or structs inside the `read` closure before returning them.
- `#expect(try ...)` fails to compile ("errors thrown from here are not handled"). Bind the throwing call to a `let` first, then `#expect` the value.
- Test suites live in `StudyReaderTests/CoreTests/` (`DatabaseMigrationTests`, `FTSSchemaTests`). Run with `-only-testing:StudyReaderTests/<Suite>`.
- Future migrations: add `v2` to `AppDatabase.migrator`. Never edit `v1`.
