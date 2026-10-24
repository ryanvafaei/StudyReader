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
- T16: schema goldens live in `StudyReaderTests/Fixtures/schema/vN.sql` (`v1.sql` = 49 lines, 13 tables, 4 FTS + shadow tables, 4 indexes, 12 triggers). Helpers: `Support/SchemaSnapshot.swift`, `Support/V1FixtureDatabase.swift`, `Support/SearchSamples.swift`. Generate a golden by running the failing test, then `cp` the path it prints (under the app container `tmp/StudyReaderSchema/`) into the Fixtures folder. Don't retype it.
- Suites: `CoreTests/SchemaSnapshotTests` (3 tests), `CoreTests/V1FixtureDatabaseTests` (4 tests). Run with `StudyReaderTests/SchemaSnapshotTests StudyReaderTests/V1FixtureDatabaseTests`.
- A test run exceeds the 120 s foreground limit. Use `run_in_background` and wait for the notification; don't poll.
