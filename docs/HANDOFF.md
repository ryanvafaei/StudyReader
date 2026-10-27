# Handoff: local Mac session → cloud session (2026-10-26)

Read this first in a new cloud session, then CLAUDE.md, ADR-0019 and ADR-0020. The local Claude Code session on the Mac updates this file before handing over; keep it current at each phase or checkpoint change.

## Where the project is
- Phase 1 (study loop). T29–T52 are committed. T52 was the first visual checkpoint.
- T52 checkpoint, manual run: `docs/checkpoints/T52-manual-2026-10-25.md`. Step 1 passed: reader tabs join the library window, so the reader work isn't blocked.
- Fix specs T52a–T52h are in `docs/tasks/phase-1/` and the Phase 1 README (T52g: category-delete plural text; T52h: Picker and layout console warnings).
- T52a–T52h are done and on `master` (CI green at `fee871d`). Full UI suite on CI (run 40424857937): 39 tests, 38 pass. The only failure is `ReaderChromeTests/testOptionCommandHTogglesTheInspector`, which waits on the ⌥⌘H decision below; never weaken it.
- T52 checkpoint, cloud run: `docs/checkpoints/T52-cloud-2026-10-27.md`. Mac-only checks are in VISUAL_CHECKS.md under "Needs a Mac" (T52a drop, T52b tab "+" and window size/position/zoom/full screen, T52d swatches in dark mode, T52e cover tint, T52h console warnings), plus tab drag-out, Open With, Dock icon count, dark mode.
- Known test gaps: `ReaderTabbingTests/joinChangesNoFrameSynchronously` only covers the property side; resize/move/zoom restore after the last reader closes is untested (zoom may be reverted).

## Decisions waiting for the user (ask, don't decide)
- ⌥⌘H collides with macOS "Hide Others" (T52 step 35). Propose a replacement (suggestion: ⌥⌘I) and the SPEC §5 change.
- Restore reader tabs after quit and relaunch, or not (T52 step 38)?
- UX items U1–U7 in the T52 report: triage and propose; build only what the user approves.

## Next steps
1. User decisions (above): ⌥⌘H replacement, tab restore after relaunch, U1–U7 triage. The ⌥⌘H one needs a SPEC §5 change, an AppCommands change and the UI test updated.
2. User checks the "Needs a Mac" list.
3. Continue with T53 (PDF reader view).

## Session notes (local session: add anything the cloud session needs to know)
- Unit suite at T52: 355 tests passed, 0 warnings.
- The user's own edits to `StudyReaderUITests/Support/` (selector helpers) are part of the UI-test setup commit; don't revert them.
- Secrets/ was removed from git history before the first push (2026-10-26). CI gets the Google config from the GOOGLE_XCCONFIG repo secret; cloud sessions don't need it. Never read or print `Secrets/`.
- A fresh clone and CI without the GOOGLE_XCCONFIG secret build with Google export not configured; this is expected (`Config/Base.xcconfig` uses `#include?`). `scripts/check-fresh-clone.sh` deliberately doesn't copy `Secrets/`.
- Cleanup left from the manual T52 run: the document "Checkpoint Drop C" is in the user's real library (not in the in-memory test library).
