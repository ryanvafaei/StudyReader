---
name: verification-techniques
description: How to substantiate StudyReader findings without editing app/test code (scratchpad sqlite3, python -I, swiftc, GRDB sources)
metadata:
  type: feedback
---

Verify findings outside the repo. Don't write test files; only the report may be written.

- GRDB sources are at `build/DerivedData/SourcePackages/checkouts/GRDB.swift`. Read them to confirm SQL shapes (upsert, FTS5 synchronize triggers, DatabaseError description).
- Reproduce schema and FTS behaviour with `sqlite3 :memory:` or `python3 -I` sqlite3 in the scratchpad, using the v1 DDL from SchemaV1.swift.
- Check Swift language claims (for example type ambiguity across modules) with tiny `swiftc -emit-module` / `-typecheck` builds in the scratchpad.
- Real library: `~/Library/Containers/com.ryanvafaei.StudyReader/Data/Library/Application Support/StudyReader/`. Inspect it read-only only (`ls -T`, `sqlite3 -readonly`). Opening it even read-only bumps the `-shm` mtime, so record the mtimes before opening.

**Why:** the bug-hunter role forbids changing code, but the report requires concrete reproductions.
**How to apply:** for every finding, either reproduce it this way or mark clearly what was derived from code rather than executed.
