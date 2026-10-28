# Handoff: local Mac session ↔ cloud session (updated 2026-10-28)

Read this first in a new cloud session, then CLAUDE.md, ADR-0019 and ADR-0020. Run `./scripts/ci.sh status` at the start. Keep this file current at each phase or checkpoint change and push it.

## Where the project is
- **Phase 1 is complete** and green on `master`: T29–T75, the checkpoint fixes T52a–T52k, T63a, T69a, T74a. All three visual checkpoints ran in cloud mode (`docs/checkpoints/T52-cloud-2026-10-27.md`, `T63-cloud-2026-10-27.md`, `T69-cloud-2026-10-28.md`, `T74-cloud-2026-10-28.md`; T74 found the Open With regression fixed by T74a).
- **Now: the end-of-phase backlog pass** (CLAUDE.md "Per phase" step 4). Planned 2026-10-28 as nine tasks, rows 47–55 in `docs/tasks/phase-1/README.md`, plus five tasks from the user's decisions the same day (T85–T89, rows 56–60). Every backlog item has a disposition at the end of `docs/BACKLOG.md` (task, done, drop with reason, Mac, or undecided).

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

After T84 come five tasks from the user's decisions of 2026-10-28 (rows 56–60):

| Task | Agent | Covers |
|---|---|---|
| T85 The library selection survives a search | ui-builder | B22 1 |
| T86 Note Markdown and tag rules in the app | ui-builder | B29 (app side), SPEC F-09 AC3, F-10 AC2 |
| T87 Note Markdown rules in the export | integrations | B29 (export side), ADR-0007 amendment, SPEC F-09 AC4 |
| T88 UI tests, part 1: search, PDF find bar, reader panel, Notes tab | ui-builder | B17 subset S1, S3, S4, F1–F3, C3, C6, C17, C18 (+ B24 2) |
| T89 UI tests, part 2: Highlights browser, unconfigured Google export | ui-builder | B17 subset H1, H2, H4–H6, H9, Export Selection alert, Settings > Google |

T88 and T89 may run their own targeted UI classes (max 2 attempts each). T85–T87 use build + unit-test filters only.

## Settled (user, 2026-10-28)
- **B17 (UI test coverage):** build the reliable subset only, as T88 and T89, after the note-rules tasks. Pixel, drag and dark-mode tests stay on the Mac list.
- **B29 (export escaping):** answered with the note rules instead. `#name` (no space) is always a tag, never a heading; `# text` is a heading. The rule is the same in the app (T86) and the export (T87). Notes support the F-07 subset plus line breaks, lists and `#`/`##`/`###` headings, and `#tag` in a document note adds the tag to the document. SPEC F-09/F-10/F-21 and ADR-0007 (amendment) were updated by the architect. **Escaping titles and authors in the export is still undecided** (BACKLOG B29); they stay raw.
- **B18 (app-wide Undo/Redo replacement):** stays as accepted; no task.
- **B22 (1):** yes, hoist the library selection into `AppSession` (T85). The library filter still resets after a search (not part of the answer; undecided, BACKLOG B22).
- **Closing UI run:** one full UI suite run by ui-tester (cloud mode) after T89, not right after T84. It checks T76–T89 for regressions and runs the new tests, before the fresh-clone check and bug-hunter. It is not one of the T63/T69/T74 checkpoints. Only spec FAILs become fix tasks; everything else goes to BACKLOG.md.

## Remaining steps
1. Backlog pass T76 → T84, in README order, through the normal loop.
2. T85 (selection hoist) → T86 (note rules, app) → T87 (note rules, export) → T88 → T89 (UI tests), same loop.
3. ONE closing full UI run by ui-tester (cloud mode, `./scripts/ci.sh status` first). Report in `docs/checkpoints/closing-cloud-<date>.md`.
4. test-runner: `./scripts/check-fresh-clone.sh`.
5. bug-hunter (report in `docs/bugs/`); its critical and high findings become fix tasks through the same loop.
6. The user's "Needs a Mac" list in VISUAL_CHECKS.md (done at the end on the Mac; nobody waits for it). It also holds O1, B2, B8 Open Link, B14 2, B15 1, B21 3, B24 1, B32, OB2, and the T86 note-look row.

## Settled user decisions (still in force)
- Highlights panel shortcut ⌥⌘I (⌥⌘H is Hide Others). Tab restore after relaunch: deferred, not in SPEC. O1 (Library tab second after Merge All Windows) waits for the real tab drag on a Mac.
- Notes: `# text` is a heading, `#name` is a tag, in the app and the export (2026-10-28; SPEC F-09, ADR-0007 amendment).

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
