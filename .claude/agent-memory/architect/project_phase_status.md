---
name: phase-status
description: Which StudyReader phases have been planned by the architect, task ranges, backlog triggers, and open questions still awaiting the user
metadata:
  type: project
---

- Phase 0: T01–T27 (+ T28). Done 2026-10-24.
- Phase 1: T29–T95 + W1, W2 (84 tasks incl. checkpoint fixes T52a–k, T63a, T69a, T74a, backlog pass T76–T90, bug-hunt fixes T91–T95). Done 2026-10-29, green. Open backlog: docs/BACKLOG.md B40–B51 + follow-ups.
- Phase 2 planned 2026-10-29 (cloud session): T96–T129 in docs/tasks/phase-2/ (33 tasks; T113 conditional on Q7, T129 = backfill conditional on Q2, runs as row 6a after T101). ADR-0021 (review data conventions), ADR-0022 (sessions/limits/keys, status Proposed until Q1/Q3/Q5/Q6/Q7 answered). ARCHITECTURE §10 and DEPENDENCIES §2/§5 amended (no FSRSDefaults.defaultWv6 in swift-fsrs 5.0.0).
- Phase 2 checkpoints: R1 after T112 (daily review), R2 after T128 (Mastery, themed, flashcards). UI tests only in T112/T128 (targeted runs, max 2). Then backlog pass (Phase 2 section of BACKLOG + user-picked old items, Q8 suggests B40, B41), fresh-clone, bug-hunter.
- Phase 2 open questions Q1–Q9 in docs/tasks/phase-2/README.md; check the user's answers before editing specs.
- Phase 2 escalation: T97 review-engine sonnet/high from the first call (must read swift-fsrs source via gh api; BLOCKED if default weights unreachable).
- Backlog L2 fixed by T96 (orchestrator removes it from docs/bugs/backlog.md). L7 still opportunistic.
- User-only edits pending: `.claude/agents/review-engine.md` names FSRSDefaults.defaultWv6; `.claude/agents/data-layer.md` mentions synchronize(withTable:).

**Why:** later planning sessions start fresh and need to know what's done and what was deferred.
**How to apply:** read before planning the next phase or a fix pass; verify against docs/tasks/ and git log since tasks may have changed during implementation. Related: [[project-conventions]].
