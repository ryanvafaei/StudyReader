---
name: phase-status
description: Which StudyReader phases have been planned by the architect, task ranges, backlog triggers, and open questions still awaiting the user
metadata:
  type: project
---

- Phase 0: T01–T27 (+ T28 English-only cleanup, committed by the orchestrator without a spec). Done 2026-10-24.
- Phase 1 planned 2026-10-24: T29–T74 in docs/tasks/phase-1/ (46 tasks), ADRs 0015–0018, ADR-0011 amended (preview signal), ARCHITECTURE §6 rule 5 (L3) and §9.1 (image placeholder per SPEC) amended. Backlog items planned: L4→T29, T27-F1→T31, L5+L6→T32, L3→T42. L2/L7 remain (L2 only bites with a future FixedNow, Phase 2).
- 2026-10-24 revision: T72 became "Google sign-in and session restore" (file T72-google-sign-in-and-session-restore.md; old T72-google-sign-in-and-signing.md is a superseded stub the orchestrator must git rm). T72 no longer changes signing/project.yml/entitlements.
- Phase 1 sonnet overrides: T41 ImportService, T65 SearchService (data-layer, sonnet/high, treat as escalated).
- Phase 1 Q1–Q7 answered 2026-10-24 (README "User decisions"): defaults kept for Q1, Q3, Q4, Q6, Q7. Q2 changed → native window tabs (T51/T52, SPEC F-01 AC4). Q5 changed → folder-access NSOpenPanel via `ImportInteraction.requestFolderAccess`, once per folder per batch, no bookmark, cancel = placeholders (T40/T41/T48, SPEC F-03 AC4, ADR-0016). T30 committed; old T72 stub deleted.
- Older open items: bundle ID prefix com.ryanvafaei unconfirmed; `.claude/agents/data-layer.md` still mentions Anchor/synchronize(withTable:) (user must edit).
- Phase 2 must consider: L2 before any test passes a future FixedNow to inMemory(now:); FSRS due dates `.storageRounded`; Review/Themed Reviews sidebar items are placeholders; Settings Review tab; Mastery filter in browser; HighlightPopover Mastery…; F-18 editedText edits (ExportHighlight already escapes editedText).

**Why:** later planning sessions start fresh and need to know what's done and what was deferred.
**How to apply:** read before planning the next phase; verify against docs/tasks/ and git log since tasks may have changed during implementation. Related: [[project-conventions]].
