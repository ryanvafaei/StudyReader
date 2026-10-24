---
name: bug-patterns
description: Recurring StudyReader bug patterns found in end-of-phase hunts (phase 0 + second pass); check each new phase for repeats
metadata:
  type: project
---

Reports: docs/bugs/phase-0.md (first pass), docs/bugs/phase-0-second-pass.md (after fixes T12–T25). All first-pass findings were verified fixed in the second pass.

- **ADR guidance that is unsafe with GRDB defaults.** ADR-0012 upsert was fixed (PK-target only). Still check new repositories for `upsert(`/`upsertAndFetch(` without `onConflict:`.
- **Date as a query argument (2nd pass M1).** Records store dates as REAL through `StudyRecord`, but a bare `Date` bound in `filter(Column("dueAt") <= now)` becomes GRDB TEXT `yyyy-MM-dd HH:mm:ss.SSS`. REAL < TEXT always, so `<=` matches every row. Grep Phase 1/2 repositories for Date arguments (DailyReviewBuilder `dueAt ≤ now`, introducedToday, lastCompletedAt).
- **Frozen migrations.** The real library is at **v2** (checked 2026-10-24; its dump equals Fixtures/schema/v2.sql). Any schema change needs v3. Check that the SchemaV1/V2 diffs are empty each phase.
- **FTS desync.** v2 uses hand-written `AFTER UPDATE OF` triggers. A full-record `update(db)` still re-indexes, so Phase 1 position and progress saves must use `update(db, columns:)` or `updateChanges`. Check that new tests call `FTSIntegrity.check`.
- **Tokenizer scope.** English-only (ADR-0014, user decision). Persian was dropped on purpose: don't report it. The open gap is a soft hyphen at a line end (`photo­\nsynthesis`), which isn't joined.
- **Test-host safety.** Detection runs at host launch, before any guard test, so the guard is after the fact. `inMemory(now:)` uses the injected clock for its cleanup cutoff, so a future `FixedNow` would wipe folders of tests still running.
- **Unknown migrations accepted silently** by older builds (GRDB skips unknown ids). Watch for this if the user builds old commits.
- Earlier patterns (fixed, still worth a grep): unindexed FK children, name clashes with imported modules (`NameClashTests`), temp-dir leaks, Date `==` after a REAL round trip (`storageRounded`).

**Why:** these are the hazards most likely to recur as Haiku/Sonnet implementers build on the Phase 0 data layer.
**How to apply:** at each phase hunt, grep for these patterns first, then do the category-based hunt. Verify test-host isolation by comparing the real container's sqlite/-wal/-shm mtimes before and after `./scripts/test.sh`.
