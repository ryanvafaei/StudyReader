# Bug backlog

Policy (user decision 2026-10-24): from now on, bug hunts get fix tasks only for critical/high findings and for mediums that get more expensive later; the rest are listed here.

"More expensive later" means the fix cost grows with use or with later work, for example anything that needs a schema migration, rewrites stored data, or changes an interface many later tasks will build on. Every other medium and every low finding goes into this file instead of becoming a task.

Each entry: finding ID and title, severity, link to the bug report section, one line on why it was deferred. Remove an entry when a task fixes it, and name that task.

## Phase 0

None. All Phase 0 findings (H1, M1–M5, L1–L7 in [`phase-0.md`](phase-0.md)) were planned as fix tasks T12–T23 before this policy existed. M3 was narrowed to English-only search (ADR-0014); its Persian/Arabic cases were dropped deliberately, not deferred.
