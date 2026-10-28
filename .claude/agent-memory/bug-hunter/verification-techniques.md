---
name: verification-techniques
description: How to substantiate StudyReader findings without editing app/test code (scratchpad sqlite3, python -I, fts5vocab, GRDB sources, read-only real library)
metadata:
  type: feedback
---

Verify findings outside the repo. Don't write test files; only the report may be written.

- GRDB sources are at `build/DerivedData/SourcePackages/checkouts/GRDB.swift/GRDB`. Read them to confirm SQL shapes (upsert, Date.databaseValue, migrator handling of unknown ids, FTS5 wrapper tokenizer).
- Reproduce schema and FTS behaviour with `sqlite3 :memory:` or `python3 -I` sqlite3 in the scratchpad. The `studyreader` tokenizer isn't available outside the app, so swap in `unicode61 remove_diacritics 2 tokenchars '­'` (the wrapped base) and reason about the Swift normalizer on top. `fts5vocab(t,'instance')` shows the exact tokens.
- Compare the real library schema with a golden: a python `mode=ro` URI dump that copies `SchemaSnapshot.dump` (whitespace collapsed, `sqlite_*`/`grdb_*` excluded), then `diff`. Opening with python `mode=ro` didn't bump the `-shm` mtime; the `sqlite3 -readonly` CLI may.
- Real library: `~/Library/Containers/com.ryanvafaei.StudyReader/Data/Library/Application Support/StudyReader/`. Inspect it read-only only, and record mtimes before and after. Compare commit times (`git log --date=format:%H:%M:%S`) with the WAL mtime to see which build last migrated it.
- Temp hygiene: count `Data/tmp/StudyReaderTests`, `StudyReader-InMemory` and `StudyReaderSchema` before and after a test run.

**Why:** the bug-hunter role forbids changing code, but the report requires concrete reproductions.
**How to apply:** for every finding, either reproduce it this way or mark clearly what was derived from code rather than executed.

Cloud sessions (Linux, 2026-10-28): no Xcode, no `build/DerivedData`, so no GRDB checkout and no real library. Use python3 -I sqlite3 (3.45) in the scratchpad for SQL semantics, read `build/ci/<run>/summary.md` for the latest CI baseline, and mark anything that depends on GRDB internals, SwiftUI click behaviour or Google's API as PLAUSIBLE with a Mac step.
