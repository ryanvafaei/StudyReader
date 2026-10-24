# Bug backlog

Policy (user decision 2026-10-24): from now on, bug hunts get fix tasks only for critical/high findings and for mediums that get more expensive later; the rest are listed here.

"More expensive later" means the fix cost grows with use or with later work, for example anything that needs a schema migration, rewrites stored data, or changes an interface many later tasks will build on. Every other medium and every low finding goes into this file instead of becoming a task.

Each entry: finding ID and title, severity, link to the bug report section, one line on why it was deferred. Remove an entry when a task fixes it, and name that task.

## Phase 0

None. All Phase 0 findings (H1, M1–M5, L1–L7 in [`phase-0.md`](phase-0.md)) were planned as fix tasks T12–T23 before this policy existed. M3 was narrowed to English-only search (ADR-0014); its Persian/Arabic cases were dropped deliberately, not deferred.

## T22 review

- **T22-R1. System SQLite logging can include SQL and the database path.** Severity: low. Source: the T22 code review ([T22 spec](../tasks/phase-0/T22-app-database-error.md)). On open or migration failures, the OS SQLite library prints `[logging]` lines that can contain the failing SQL and the library file's path. This output comes from the OS, not our logger, so our no-PII logging rule (ARCHITECTURE §14) can't control it. Deferred: it only reaches the local console and unified log, the UI never shows it (T23), and no task is planned.
