---
name: app-database-error-notes
description: T22 AppDatabaseError mapping, prepareDatabase schema-read-first rule, and corrupt-file test fixtures
metadata:
  type: reference
---

- Files: `StudyReader/Core/Database/AppDatabaseError.swift`, `AppDatabase.makeShared` / `logged(_:stage:)`, tests in `StudyReaderTests/CoreTests/AppDatabaseErrorTests.swift`.
- `makeConfiguration()`'s `prepareDatabase` must read the schema (`Row.fetchOne(db, sql: "SELECT * FROM sqlite_master LIMIT 1")`) before `db.add(tokenizer:)`. GRDB's registration fatalErrors if `SELECT fts5(?)` can't prepare on a damaged file, so the read must come first to get a thrown NOTADB/CORRUPT.
- Corrupt-page fixture: plain `DatabaseQueue` with `CREATE TABLE t (x)`, then overwrite bytes 100..<512 via `FileHandle(forUpdating:)`. It reports `.damaged(code: 11)`.
- `#expect(throws: DatabaseError.self)` returns an optional error; `#expect(error?.resultCode == .SQLITE_NOTADB)` works.
- Test runs take ~1 s for this suite but the background notification can arrive before `build/test.log` is complete. Wait for the completion notice, don't tail the log early.
