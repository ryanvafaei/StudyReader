---
name: migration-v2-notes
description: T19 migration v2 (FK indexes, studyreader FTS tables, column-filtered triggers) files, golden flow, and Swift Testing pitfalls hit while writing its tests
metadata:
  type: project
---

v2 lives in `StudyReader/Core/Database/SchemaV2.swift`, registered in `AppDatabase.migrator`. Golden: `StudyReaderTests/Fixtures/schema/v2.sql`, copied byte-for-byte from `~/Library/Containers/com.ryanvafaei.StudyReader/Data/tmp/StudyReaderSchema/v2.actual.sql` after the first failing `SchemaSnapshotTests` run. Tests: `StudyReaderTests/CoreTests/MigrationV2Tests.swift`.

**Why:** the failing-golden run is the only supported way to generate a golden (ADR-0013). Never hand-edit it.

**How to apply:**
- `#expect(try f(x) == 1)` does not compile in this Swift Testing setup ("errors thrown from here are not handled"). Bind first: `let v = try f(x)` then `#expect(v == 1)`.
- `FTSIntegrity.check` writes (`'integrity-check'` insert). Never call it inside `reader.read`. Use `writer.write`.
- Trace checks for "no reindex" use `db.trace(options:_:)` collected in a `Mutex`, and `db.trace()` with no arguments stops tracing.
- Prefix MATCH: the `matchCount` helper wraps its term in quotes, so `term + "*"` becomes a quoted literal. For prefix queries, build the SQL with `"\"" + term + "\"*"` directly (T19 review fix, foldedSearchOnLiveTables).
