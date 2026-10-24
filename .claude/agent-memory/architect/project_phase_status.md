---
name: phase-status
description: Which StudyReader phases have been planned by the architect, task ranges, and open questions still awaiting the user
metadata:
  type: project
---

- Phase 0 planned 2026-10-23: T01–T11 in docs/tasks/phase-0/ (ADR-0011, ADR-0012).
- Phase 0 bug hunt 2026-10-24 (docs/bugs/phase-0.md): H1 -> T12. User decided 2026-10-24: new v2 migration (v1 frozen, real library at v1 with 0 docs), fix all M1–M5/L1–L7 now, do L6 renames. Planned as T13–T23 (ADR-0013 migration policy/v2, ADR-0014 tokenizer; ADR-0011/0012 amended). T19 upgrades the user's real library to v2 on next launch.
- 2026-10-24: T24 (LaunchView minWidth 700/minHeight 450 on root Group; scene sizing untouched) added from T23 visual check. Backlog got a "T22 review" section: T22-R1 OS SQLite [logging] may print SQL + db path (low, accepted, also in ARCHITECTURE §14).
- 2026-10-24: T25 from T24 visual check: shared `MainWindowLayout.minWidth/minHeight` (900x600, caseless enum in App/, no actor annotation) used by RootView + LaunchView; 700x450 superseded. Later window/sheet sizing should reuse MainWindowLayout, not literals.
- Flagged to user 2026-10-24: `.claude/agents/data-layer.md` still says Anchor + synchronize(withTable:)/unicode61 (agents can't edit it); AppDatabaseError message wording.
- Answered 2026-10-24: tokenizer English-only (T16/T18/T19 rewritten: SearchSamples, fixture's 2nd doc is English "Lecture notes"); team ID 597KGSTZWJ (set only in E1.8); T18 runs on sonnet/high; backlog policy (docs/bugs/backlog.md).
- Open: SPEC non-functional row still says Persian content must render and highlight (not search) — fine with English-only search, but confirm. Bundle ID prefix com.ryanvafaei OK?
- Phase 1 must include: launch cleanup of orphan Documents/<id> folders (use FileStore.documentFolderIds, canonical only) + re-queue pending extraction; DocumentRepository delete and metadataUpdate (column-limited updates); Hashing helper; E1.8 adds keychain-access-groups + DEVELOPMENT_TEAM.

**Why:** later planning sessions start fresh and need to know what's done and what was deferred.
**How to apply:** read before planning the next phase; verify against docs/tasks/ and git log since tasks may have changed during implementation. Related: [[project-conventions]].
