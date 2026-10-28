# Handoff: local Mac session ↔ cloud session (updated 2026-10-28, after the Phase 1 bug hunt)

Read this first in a new cloud session, then CLAUDE.md, ADR-0019 and ADR-0020. Run `./scripts/ci.sh status` at the start. Keep this file current at each phase or checkpoint change and push it.

## Where the project is
- **Phase 1 is complete** and green on `master`: T29–T75, the checkpoint fixes T52a–T52k, T63a, T69a, T74a. All three visual checkpoints ran in cloud mode (`docs/checkpoints/T52-cloud-2026-10-27.md`, `T63-cloud-2026-10-27.md`, `T69-cloud-2026-10-28.md`, `T74-cloud-2026-10-28.md`; T74 found the Open With regression fixed by T74a).
- **The end-of-phase backlog pass is done:** T76–T89 are approved, committed and pushed (last: `a63c6c3` T89).
- **Closing UI run done** (2026-10-28, ui-tester, cloud mode): `docs/checkpoints/closing-cloud-2026-10-28.md`. 93 tests: 91 passed, **1 SPEC FAIL** (`ExternalOpenTests/testDuplicateOpenWithStillShowsTheSummaryAlert`, Open With right after launch with only the library open imports nothing, 2/2, regression between T74a `ea3e7e1` and `a63c6c3`), **1 flake** (H9, passed on the re-run; BACKLOG B38). UX items and the H9 note are BACKLOG B36, B38; B37 (NotesTabTests warning) and B39 (failure attachment) are folded into T90; NEEDS HUMAN rows are in VISUAL_CHECKS.md "Needs a Mac".
- **T90 is done** (Open With fix, approved, CI green; cause unconfirmed, Mac row T90). The fresh-clone check passed (run `40739072211`).
- **Bug hunt done** (2026-10-28): `docs/bugs/phase-1.md`, critical 0, high 2, medium 5, low 10. The user decided the same day: H1, H2, M1+M2, M4, M5 become fix tasks T91–T95 (rows 62–67 in `docs/tasks/phase-1/README.md`); M3, L1–L10 and the Google Picker idea are BACKLOG only (B40–B51).
- **Now: T91** (row 62, pdf-engine), then T92a → T92b → T93 → T94 → T95, one at a time through the normal loop. None of them runs UI tests.
- Backlog pass history: planned 2026-10-28 as nine tasks, rows 47–55 in `docs/tasks/phase-1/README.md`, plus five tasks from the user's decisions the same day (T85–T89, rows 56–60). Every backlog item has a disposition at the end of `docs/BACKLOG.md` (task, done, drop with reason, Mac, or undecided).

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
| T90 Open With right after launch (closing-run fix, row 61) | ui-builder | closing-run SPEC FAIL (F-02), B37, B39 |

T88 and T89 may run their own targeted UI classes (max 2 attempts each). T85–T87 use build + unit-test filters only.

Bug hunt fix tasks (rows 62–67, planned 2026-10-28 by the architect):

| Task | Agent | Covers |
|---|---|---|
| T91 ⌘Z never deletes an annotated auto-highlight | pdf-engine | H1 |
| T92a Exports go into the app's own "StudyReader" Drive folder (service) | integrations | H2 |
| T92b Settings > Google: no folder-link field, "Open in Drive", one-time notice | ui-builder | H2 |
| T93 Quitting never loses the last typed note text | ui-builder | M4 |
| T94 Drive errors mapped by reason; queued exports always retried | integrations | M1, M2 |
| T95 One link filter for every clickable link | pdf-engine | M5 |

## Settled (user, 2026-10-28, bug hunt)
- **Order:** T91, T92 (split into T92a then T92b), T93, T94, T95; then the fresh-clone check and the Phase 1 summary. Each through the normal loop (implementer, then reviewer + CI).
- **H1 (T91):** annotating an auto-highlight ends its undo window. Chosen rule: Undo deletes only a bare highlight (no note, tags or edited text, checked in the delete's own transaction); the undo mark also drops when a note or edited text shows up or the popover opens on it.
- **H2 (T92a/T92b):** the export target is a folder named "StudyReader" that the app creates in Drive on the first export; its ID is stored durably per account (UserDefaults, keyed by a hash of the email). The pasted-folder-link field is removed from Settings; an "Open in Drive" link to the app folder stays; an older pasted folder ID is ignored with a one-line notice shown once. Deleted or trashed folder: recreated silently. Moved folder: still works (stored ID). Concurrent first exports: one actor-wide folder gate, so one folder. Other account / sign-out: per-account entry. Architect's addition: before creating, the app looks up an app-visible "StudyReader" folder (`files.list`), so a reinstall or a second Mac reuses it. ADR-0018 amended: `drive.file` only covers files the app created or the user picked with the Google Picker; the Picker (browser flow, Picker API, `trigger_onepick`) is possible later work, BACKLOG B51 only.
- **M4 (T93):** flush pending note text (and the reading position) on quit via `applicationShouldTerminate` and a weak `PendingWrites` registry; window close keeps the existing `onDisappear` flushes.
- **M1+M2 (T94):** 403 storage quota / rate limit / daily limit / no access are `failed` and keep the Doc link (rate limits back off first); only 404 or a trashed Doc is "Doc missing"; unknown 403 → `failed`. Export Selection offline says "try again" instead of promising a later run; manual exports that end queued while online are retried by the scheduler (`manualExportEnded`); launch retry already exists.
- **M5 (T95):** one `LinkPolicy` (http, https, mailto) applied inside `RichTextView` and `NoteMarkdownView`.
- **Backlog only:** M3, L1–L10 (incl. the fourth T87 hole L7 and the B29 extension L8), the Google Picker; the T90 follow-up on `HighlightsBrowserModel.observe` is real but narrow (BACKLOG Follow-ups).
- **UI tests:** none of T91–T95 runs UI tests. T92b changes one `SettingsTests` expectation, so after T95 ui-tester runs one targeted `./scripts/uitest.sh StudyReaderUITests/SettingsTests`.

## Settled (user, 2026-10-28)
- **B17 (UI test coverage):** build the reliable subset only, as T88 and T89, after the note-rules tasks. Pixel, drag and dark-mode tests stay on the Mac list.
- **B29 (export escaping):** answered with the note rules instead. `#name` (no space) is always a tag, never a heading; `# text` is a heading. The rule is the same in the app (T86) and the export (T87). Notes support the F-07 subset plus line breaks, lists and `#`/`##`/`###` headings, and `#tag` in a document note adds the tag to the document. SPEC F-09/F-10/F-21 and ADR-0007 (amendment) were updated by the architect. **Escaping titles and authors in the export is still undecided** (BACKLOG B29); they stay raw.
- **B18 (app-wide Undo/Redo replacement):** stays as accepted; no task.
- **B22 (1):** yes, hoist the library selection into `AppSession` (T85). The library filter still resets after a search (not part of the answer; undecided, BACKLOG B22).
- **Closing UI run:** one full UI suite run by ui-tester (cloud mode) after T89, not right after T84. It checks T76–T89 for regressions and runs the new tests, before the fresh-clone check and bug-hunter. It is not one of the T63/T69/T74 checkpoints. Only spec FAILs become fix tasks; everything else goes to BACKLOG.md.

## Remaining steps
1. ~~Backlog pass T76 → T84~~ done.
2. ~~T85 → T89~~ done.
3. ~~Closing full UI run~~ done (`docs/checkpoints/closing-cloud-2026-10-28.md`, 93 tests, 1 SPEC FAIL, 1 flake).
4. ~~T90~~ done. ~~Fresh-clone check~~ passed. ~~bug-hunter~~ done (`docs/bugs/phase-1.md`: 0 critical, 2 high, 5 medium, 10 low).
5. **T91 → T92a → T92b → T93 → T94 → T95**, in that order, normal loop (implementer; then code-reviewer + test-runner CI in parallel; commit and push). Agents and escalation per CLAUDE.md: pdf-engine/integrations/ui-builder are Sonnet (1st rejection: effort high; 2nd: ask the user). Build + unit-test filters only.
6. ui-tester: one targeted UI run, `./scripts/uitest.sh StudyReaderUITests/SettingsTests` (T92b changed one expectation). Only a spec FAIL becomes a fix task.
7. test-runner: `./scripts/check-fresh-clone.sh`.
8. The Phase 1 summary.
9. The user's "Needs a Mac" list in VISUAL_CHECKS.md (done at the end on the Mac; nobody waits for it). It also holds O1, B2, B8 Open Link, B14 2, B15 1, B21 3, B24 1, B32, OB2, the T86 note-look row, the closing-run rows (T90 Open With right after launch, B36 bulk bar, `#tag` styling, Settings > Google unconfigured, B38 H9), and the bug-hunt rows T92 (1) first export creates the folder and the Doc, T92 (2) moved/trashed folder (the orchestrator adds the T91, T92b, T93 and T95 rows from the reports). The T73 rows still mention the old folder field; T92b supersedes that part.

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
