# Handoff: local Mac session ↔ cloud session (updated 2026-10-27)

Read this first in a new cloud session, then CLAUDE.md, ADR-0019 and ADR-0020. Keep it current at each phase or checkpoint change, and push it.

## Where the project is
- Phase 1 (study loop). T29–T52 are committed. T52 was the first visual checkpoint.
- T52 checkpoint, manual run: `docs/checkpoints/T52-manual-2026-10-25.md`. Step 1 passed: reader tabs join the library window, so the reader work isn't blocked.
- T52a–T52h are done and on `master` (CI green at `fee871d`). Full UI suite on CI (run 40424857937): 39 tests, 38 pass. The only failure is `ReaderChromeTests/testOptionCommandHTogglesTheInspector` (⌥⌘H); T52k replaces it with `testOptionCommandITogglesTheInspector`. Never weaken it.
- T52 checkpoint, cloud run: `docs/checkpoints/T52-cloud-2026-10-27.md`.
- New fix specs from the user's triage (2026-10-27), in `docs/tasks/phase-1/` and the Phase 1 README rows 24k, 24i, 24j: **T52k** (⌥⌘I), **T52i** (library polish), **T52j** (sheets, imports, Settings). U7 went into T53's spec.
- Known test gaps: `ReaderTabbingTests/joinChangesNoFrameSynchronously` only covers the property side; resize/move/zoom restore after the last reader closes is untested (zoom may be reverted).

## User decisions (2026-10-27)
- **Highlights panel shortcut: ⌥⌘I** (⌥⌘H is the system's Hide Others). SPEC §5 and F-06, and the T52 and T63 specs, are updated. **T52k** does the code and the UI test.
- **Tab restore after quit and relaunch: deferred (user decision 2026-10-27), not in SPEC.** Nothing restores reader tabs; no task builds it. T52 step 38 is closed as "not required".
- **U1–U7 triage** (T52 manual report):
  - U1 focus-ring line at the library's left edge, U3 clearing the grid selection (click on empty space, Escape), U4 placeholder covers vs selection fill (with S2), plus S3 cover hairline and `.accessibilityHidden(true)` on the hidden "Open Selected Document" button → **T52i**.
  - U2 metadata sheet loading flash, U5 no alert for a successful import (alerts stay for problems; VoiceOver announcement instead), U6 Settings colour-label rows and cut-off list, plus S1 blank-title error next to Title → **T52j**.
  - U7 failed-load reader hides the colour menu and inspector toggle → **T53** (shared chrome; T55 only calls `engineFailed(_:)`).
- **O1 stays open:** after Window > Move Tab to New Window + Merge All Windows, the Library tab comes second. Not specced. It waits for the user's real tab-drag check on a Mac; decide afterwards whether the Library tab must stay first.

## Standing rules
- **Library window Return and Escape.** `LibraryView`'s hidden "Open Selected Document" button (T52a) catches Return window-wide while the Library section is shown, and after T52i a hidden "Clear Selection" button catches Escape. Any task that adds a text field or search field to the library window must keep Return (and Escape) in that field from opening the selected document or clearing the selection, with a UI test. The "Constraint" note is in T52i, T66 (search field) and T69 (Highlights browser fields, safe only while `LibraryView` is out of the hierarchy). Add it to every future spec that puts a text field in the main window.
- **Review log lines** record implementer and reviewer: `date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason`. The format is also at the top of `docs/tasks/phase-1/README.md` and in `docs/tasks/_TEMPLATE.md`. T52a–T52h have a backfilled implementer line.
- **Keep CI minutes down.** While fixing, use targeted runs: `./scripts/test.sh StudyReaderTests/<Suite>[/<test>]` and `./scripts/uitest.sh StudyReaderUITests/<Class>[/<test>]` (both go through `ci.sh` in a cloud session). The full UI suite runs only at checkpoints. The per-task full unit run (test-runner) stays.
- **"Needs a Mac" list:** the user does it at the end of the project. It stays in VISUAL_CHECKS.md and nobody waits for it; keep adding Mac-only steps there with the task ID.

## Next steps
1. T52k (ui-builder): ⌥⌘I in `AppCommands`, the doc comment in `ReaderModel`, the renamed UI test.
2. T52i (ui-builder): library polish.
3. T52j (ui-builder): metadata sheet, quiet imports, Settings rows (four parts; larger than usual).
4. T53 (pdf-engine): PDF reader view, including U7.
- Pending small doc edits outside `docs/` (the architect writes only `docs/`): VISUAL_CHECKS.md T52 row "⌥⌘H" → "⌥⌘I" and "restore after quit" → "(restore after quit: deferred, not in SPEC)"; the ui-tester memory note `.claude/agent-memory/ui-tester/studyreader-ui-facts.md` lines about ⌥⌘H and the "Import finished" alert (update after T52k and T52j land).

## Session notes (local session: add anything the cloud session needs to know)
- Unit suite at T52: 355 tests passed, 0 warnings.
- The user's own edits to `StudyReaderUITests/Support/` (selector helpers) are part of the UI-test setup commit; don't revert them.
- Secrets/ was removed from git history before the first push (2026-10-26). CI gets the Google config from the GOOGLE_XCCONFIG repo secret; cloud sessions don't need it. Never read or print `Secrets/`.
- A fresh clone and CI without the GOOGLE_XCCONFIG secret build with Google export not configured; this is expected (`Config/Base.xcconfig` uses `#include?`). `scripts/check-fresh-clone.sh` deliberately doesn't copy `Secrets/`.
- Cleanup left from the manual T52 run: the document "Checkpoint Drop C" is in the user's real library (not in the in-memory test library).
- Mac-only checks from the T52 checkpoint are in VISUAL_CHECKS.md under "Needs a Mac" (T52a drop, T52b tab "+" and window size/position/zoom/full screen, T52d swatches in dark mode, T52e cover tint, T52h console warnings), plus tab drag-out (also for O1), Open With, Dock icon count, dark mode. T52i and T52j add their own rows when they land.
