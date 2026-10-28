# Handoff: local Mac session ↔ cloud session (updated 2026-10-28)

Read this first in a new cloud session, then CLAUDE.md, ADR-0019 and ADR-0020. Run `./scripts/ci.sh status` at the start. Keep this file current at each phase or checkpoint change and push it.

## Where the project is
- **Phase 1 is complete** and green on `master`: T29–T75, the checkpoint fixes T52a–T52k, T63a, T69a, T74a. All three visual checkpoints ran in cloud mode (`docs/checkpoints/T52-cloud-2026-10-27.md`, `T63-cloud-2026-10-27.md`, `T69-cloud-2026-10-28.md`, `T74-cloud-2026-10-28.md`; T74 found the Open With regression fixed by T74a).
- **Now: the end-of-phase backlog pass** (CLAUDE.md "Per phase" step 4). Planned 2026-10-28 as nine tasks, rows 47–55 in `docs/tasks/phase-1/README.md`. Every backlog item has a disposition at the end of `docs/BACKLOG.md` (task, done, drop with reason, Mac, or user decision).

| Task | Agent | Covers |
|---|---|---|
| T76 Search hardening | data-layer | B20, B21, B22 3 |
| T77 PDF reader and rich-text robustness | pdf-engine | B5, B9, B11 rest, B12 3, B14 1/3 |
| T78 Highlight, tag and export queries | data-layer | B25, B30 1–3/5, B16 3 (repo), B33 5 |
| T79 Text reader and anchoring | pdf-engine | B6 rest, B7, B8 comment, B10, B18 painting |
| T80 Export service and scheduler hardening | integrations | B30 4/5, B31 3/4, B34 |
| T81 Highlight controllers and undo mark | pdf-engine | B13 1–3, B19 1 |
| T82 Reader panel, Notes tab and popover polish | ui-builder | B15 2–6, B16 1/3–6, B18 test |
| T83 Export UI guards, browser and Settings polish | ui-builder | B26 2, B27 2, B33 1–4, B35 2 |
| T84 UI-test hygiene and deterministic seed | ui-builder | OB1, B4, B23 3, B27 1, B28 2/3, B35 1/3 |

Only T84 runs XCUITests (its own targeted classes, max 2 attempts). T76–T83 use build + unit-test filters only.

## Decisions waiting for the user (no task built until answered)
1. **B17: how much XCUITest coverage to build now.** Proposals: T63 report C3–C8, C11–C19; T69 report S1–S5, F1–F5, H1–H9; T74 report unconfigured Settings > Google tab, "Export Selection…" not-configured alert, Export sheet pickers and File-menu enabled state. Recommendation: one or two test-writing tasks (T85, T86) right after T84, before bug-hunter, limited to reliable non-pixel, non-drag tests: S1, S3, S4, F1–F3 (F2 also settles B24 Shift-Return), H1, H2, H4–H6, H9, C3, C6, C17, C18 and the unconfigured Google/export tests. Pixel, drag and dark-mode tests (C5, C13, C14, C15) stay on the Mac list.
2. **B29: notes, document notes, titles and authors are exported raw** (only highlight bodies are neutralised). Recommendation: escape titles and authors (plain metadata, `*`/`_` shouldn't style them); keep notes raw (users write Markdown in notes and the Notes preview renders it); record it in ADR-0007. Goldens don't change. If accepted it is a small integrations task.
3. **B18: the app-wide Undo/Redo replacement** (static titles, never disabled) was accepted for now. Recommendation: keep it until you try it on the Mac (VISUAL_CHECKS "Backlog pass" row); if it bothers you, plan the narrow per-view `undo:` alternative then.
4. **B22 1: library selection resets after a search** (LibraryView is replaced while a query is active; sort and layout already persist in Settings). Recommendation: yes, hoist the selection into `AppSession` (a small ui-builder task), so clearing the search returns to the same selection.
5. **Closing UI run:** XCUITests normally run only at T63/T69/T74. Recommendation: let ui-tester run the full UI suite once after T84 (cloud mode), since T76–T83 touch reader, browser, export and Settings code with no UI run of their own.

## Remaining steps
1. Backlog pass T76 → T84, in README order, through the normal loop.
2. Any tasks from the decisions above (T85+), if the user approves them.
3. test-runner: `./scripts/check-fresh-clone.sh`.
4. bug-hunter (report in `docs/bugs/`); its critical and high findings become fix tasks through the same loop.
5. The user's "Needs a Mac" list in VISUAL_CHECKS.md (done at the end on the Mac; nobody waits for it). It also holds O1, B2, B8 Open Link, B14 2, B15 1, B21 3, B24 1, B32, OB2.

## Settled user decisions (still in force)
- Highlights panel shortcut ⌥⌘I (⌥⌘H is Hide Others). Tab restore after relaunch: deferred, not in SPEC. O1 (Library tab second after Merge All Windows) waits for the real tab drag on a Mac.

## Standing rules
- **Library window Return and Escape.** LibraryView's hidden buttons catch Return (open selected) and Escape (clear selection) window-wide while the Library section is shown. Any task that adds a text or search field to the main window must keep Return and Escape in that field from opening or clearing, with a UI test. Put the "Constraint" note into every such spec.
- **Review log lines:** `date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason`.
- **Speed rules (user, 2026-10-27):** no polish tasks mid-phase (non-FAIL findings go to BACKLOG.md); per task: implementer → CI build + unit tests (test-runner) with code-reviewer in parallel → commit and push; approval counts only with green CI; no per-task UI runs except tasks that fix or add XCUITests (targeted classes only); don't wait for master CI between tasks; check `./scripts/ci.sh status` at checkpoints. Never run two CI jobs at once (overlapping `ci.sh` runs cancel each other).
- **Agents:** ui-builder on Sonnet medium (escalation: high, then ask the user); data-layer and review-engine on Haiku (escalation: high, then Sonnet high); pdf-engine and integrations on Sonnet high.
- **"Needs a Mac":** keep adding Mac-only steps to VISUAL_CHECKS.md with the task ID.

## Session notes
- The user's edits to `StudyReaderUITests/Support/` (selector helpers) are part of the UI-test setup; don't revert them (T84 only adds a helper).
- Never read or print `Secrets/`. CI gets the Google config from the GOOGLE_XCCONFIG repo secret; a fresh clone and CI without it build with Google export "not configured" (expected; `Config/Base.xcconfig` uses `#include?`).
- The real library on the Mac still has the document "Checkpoint Drop C" from the manual T52 run.
