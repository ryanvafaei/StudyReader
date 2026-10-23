---
name: phase-status
description: Which StudyReader phases have been planned by the architect, task ranges, and open questions still awaiting the user
metadata:
  type: project
---

- Phase 0 planned 2026-10-23: T01–T10 in docs/tasks/phase-0/ (ADR-0011, ADR-0012 added; small pointer edits to ARCHITECTURE §2.2 and §4).
- Phase 0 bug hunt 2026-10-24 (docs/bugs/phase-0.md): H1 -> T12 (ADR-0012 upsert amendment). M1–M5, L1–L7 unscheduled; M2/M3/L5 need a v2 migration decision from the user; L6 suggests renaming CardState/Anchor (ReviewCardState/HighlightAnchor) before Phase 1 depends on them.
- Open at planning time (check answers before Phase 1): bundle ID prefix com.ryanvafaei OK?; Apple team ID needed before E1.8 (keychain entitlement); OK to commit Package.resolved via .gitignore exceptions; confirm record renames.
- Phase 1 must include: launch cleanup of orphan Documents/<id> folders + re-queue pending extraction; DocumentRepository delete (FileStore.deleteDocumentFolder) and metadataUpdate; Hashing helper; the E1.8 task adds keychain-access-groups + DEVELOPMENT_TEAM to project.yml.

**Why:** later planning sessions start fresh and need to know what's done and what was deferred.
**How to apply:** read before planning the next phase; verify against docs/tasks/ since tasks may have changed during implementation. Related: [[project-conventions]].
