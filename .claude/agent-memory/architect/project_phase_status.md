---
name: phase-status
description: Which StudyReader phases have been planned by the architect, task ranges, and open questions still awaiting the user
metadata:
  type: project
---

- Phase 0 planned 2026-10-23: T01–T11 in docs/tasks/phase-0/ (ADR-0011, ADR-0012).
- Phase 0 bug hunt 2026-10-24 (docs/bugs/phase-0.md): H1 -> T12. User decided 2026-10-24: new v2 migration (v1 frozen, real library at v1 with 0 docs), fix all M1–M5/L1–L7 now, do L6 renames. Planned as T13–T23 (ADR-0013 migration policy/v2, ADR-0014 tokenizer; ADR-0011/0012 amended). T19 upgrades the user's real library to v2 on next launch.
- Flagged to user 2026-10-24: `.claude/agents/data-layer.md` still says Anchor + synchronize(withTable:)/unicode61 (agents can't edit it); tokenizer extras beyond the bug report (NFKC, soft hyphen, ۀ fold) and the not-folded list (alef forms, teh marbuta, digits); AppDatabaseError message wording.
- Older open questions (check answers before Phase 1): bundle ID prefix com.ryanvafaei OK?; Apple team ID needed before E1.8; Package.resolved committed via .gitignore exception.
- Phase 1 must include: launch cleanup of orphan Documents/<id> folders (use FileStore.documentFolderIds, canonical only) + re-queue pending extraction; DocumentRepository delete and metadataUpdate (column-limited updates); Hashing helper; E1.8 adds keychain-access-groups + DEVELOPMENT_TEAM.

**Why:** later planning sessions start fresh and need to know what's done and what was deferred.
**How to apply:** read before planning the next phase; verify against docs/tasks/ and git log since tasks may have changed during implementation. Related: [[project-conventions]].
