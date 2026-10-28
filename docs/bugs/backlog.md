# Bug backlog

Policy (user decision 2026-10-24): from now on, bug hunts get fix tasks only for critical/high findings and for mediums that get more expensive later; the rest are listed here.

"More expensive later" means the fix cost grows with use or with later work, for example anything that needs a schema migration, rewrites stored data, or changes an interface many later tasks will build on. Every other medium and every low finding goes into this file instead of becoming a task.

Each entry: finding ID and title, severity, link to the bug report section, one line on why it was deferred. Remove an entry when a task fixes it, and name that task.

## Phase 0

None. All Phase 0 findings (H1, M1–M5, L1–L7 in [`phase-0.md`](phase-0.md)) were planned as fix tasks T12–T23 before this policy existed. M3 was narrowed to English-only search (ADR-0014).

## Phase 1

The deferred Phase 1 findings (M3 and L1–L10 from [`phase-1.md`](phase-1.md), plus the Google Picker idea) are kept in [`docs/BACKLOG.md`](../BACKLOG.md) as B40–B51, with their dispositions (user decision 2026-10-28). H1, H2, M1, M2, M4 and M5 are fix tasks T91–T95.

## T22 review

- **T22-R1. System SQLite logging can include SQL and the database path.** Severity: low. Source: the T22 code review ([T22 spec](../tasks/phase-0/T22-app-database-error.md)). On open or migration failures, the OS SQLite library prints `[logging]` lines that can contain the failing SQL and the library file's path. This output comes from the OS, not our logger, so our no-PII logging rule (ARCHITECTURE §14) can't control it. Deferred: it only reaches the local console and unified log, the UI never shows it (T23), and no task is planned.

## Phase 0 second pass

Source: [`phase-0-second-pass.md`](phase-0-second-pass.md) (2026-10-24). Its only medium, M1, was fixed by T26. By user decision on 2026-10-24, L1 was fixed by T27 and the `DateStorageTests` part of L7 by T26; both are committed and removed here. L4 was fixed by T29 and removed here. L5 and L6 were fixed by T32 and removed here. T27-F1 was resolved by T31 and removed. L3 was fixed by T42 (ARCHITECTURE §6 rule 5 amended) and removed. The other lows have no tasks. Plan each one as a task when its "revisit when" trigger is reached, then remove it here and name the task.

- **L2. `inMemory(now:)` uses the injected clock for temp-folder cleanup.** Severity: low. [Report](phase-0-second-pass.md#l2-inmemorynow-uses-the-injected-domain-clock-to-judge-folder-age-so-a-future-fixednow-deletes-the-folders-of-tests-that-are-still-running). A future `FixedNow` makes every existing `StudyReader-InMemory/<UUID>` folder look stale, so parallel tests lose their folders.
  - Suggested fix: compute the one-hour cleanup cutoff from the real wall clock or the folders' file-system dates, independent of the injected `Now`, or clean up only in `defaultFactory`. Add the report's failing test.
  - Suggested agent: ui-builder.
  - Revisit when: opportunistic. At the latest before any test passes a future `FixedNow` to `AppEnvironment.inMemory(now:)` (Phase 2 scheduling tests).
- **L7. Some tests that write FTS-indexed tables don't end with `FTSIntegrity.check`.** Severity: low. [Report](phase-0-second-pass.md#l7-several-tests-that-write-fts-indexed-tables-dont-end-with-ftsintegritycheck-although-architecture-15-says-every-one-does). `UpsertConventionTests`, `ReviewExportRecordTests` and `RecordCodingTests` break the ARCHITECTURE §15 rule. A manual check found the index consistent. (The `DateStorageTests` part was fixed by [T26](../tasks/phase-0/T26-date-query-arguments.md).)
  - Suggested fix: add `try FTSIntegrity.check(db)` at the end of the write closures in those three suites. Don't narrow the ARCHITECTURE sentence.
  - Suggested agent: data-layer.
  - Revisit when: opportunistic, for example the next task that touches one of those test files. Phase 1 specs that write FTS tables must keep requiring the check.
