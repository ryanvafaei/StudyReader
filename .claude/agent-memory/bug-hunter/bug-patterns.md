---
name: bug-patterns
description: Recurring StudyReader bug patterns found in end-of-phase hunts (phase 0 onward); check each new phase for repeats
metadata:
  type: project
---

Patterns seen so far (phase 0 report: docs/bugs/phase-0.md):

- **ADR guidance that is unsafe with GRDB defaults.** ADR-0012 says "use update/upsert/save". GRDB upsert without `onConflict:` fires on ANY unique constraint (document.fileHash, tag.name, category.name) and overwrites another row. Check new repositories for untargeted `upsert`/`upsertAndFetch`.
- **Editing frozen migration v1.** The user's real library already has v1 applied (checked 2026-10-24). Schema fixes must be new migrations. Check whether `SchemaV1.swift` changed in the phase's diff.
- **FTS desync invisible to tests.** Tests only MATCH single words. Look for `INSERT OR REPLACE`, `persistenceConflictPolicy`, VACUUM, and missing `'integrity-check'` assertions.
- **Persian/Arabic search.** unicode61 splits on ZWNJ and Arabic harakat and doesn't fold ي/ك to ی/ک. Recheck once SearchService lands.
- **Unindexed FK child columns** (reviewLog.cardId etc.) make cascades scan whole tables.
- **Name clashes with imported modules** that only show up in test files importing both (CardState vs FSRS, Anchor vs SwiftUI).
- **Temp-dir leaks** from TestFileStore / AppEnvironment.inMemory().
- **Date `==` after REAL round-trip** fails for about 46% of fractional timestamps.

**Why:** these are the hazards most likely to recur as Haiku/Sonnet implementers build on the Phase 0 data layer.
**How to apply:** at each phase hunt, grep for these patterns first, then do the category-based hunt. Verify test-host isolation by checking the real container's sqlite/-shm mtimes against test-run times. Use read-only `sqlite3 -readonly` only; never write the real library.
