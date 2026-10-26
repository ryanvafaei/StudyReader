# Handoff: local Mac session → cloud session (2026-10-26)

Read this first in a new cloud session, then CLAUDE.md, ADR-0019 and ADR-0020. The local Claude Code session on the Mac updates this file before handing over; keep it current at each phase or checkpoint change.

## Where the project is
- Phase 1 (study loop). T29–T52 are committed. T52 was the first visual checkpoint.
- T52 checkpoint, manual run: `docs/checkpoints/T52-manual-2026-10-25.md`. Step 1 passed: reader tabs join the library window, so the reader work isn't blocked.
- Fix specs T52a–T52h are in `docs/tasks/phase-1/` and the Phase 1 README (T52g: category-delete plural text; T52h: Picker and layout console warnings).
- UI tests (`StudyReaderUITests/`, ADR-0019): cloud path verified 2026-10-26 (`./scripts/ci.sh uitest` posts the summary and downloads logs and screenshots to `build/ci/<run id>/`). Full suite on CI: 39 tests, 29 pass, 10 fail. Every failure matches a T52 finding, none is new, and they must stay failing until their fix task (never weaken them):
  - `LibraryOpenTests/testListViewReturnOpensTheSelectedRow` → T52a
  - `LibraryOpenTests/testOpeningAReaderTabKeepsTheWindowSize` → T52b
  - `ReaderChromeTests/testMissingOriginalShowsErrorAndKeepsTheTitle`, `testOpenReaderSubtitleFollowsACategoryDeletion` → T52c
  - `ReaderChromeTests/testHighlightColorMenuShowsColouredSwatchesAndKeepsTheChoice` → T52d
  - `LibraryCoverTests/testLandscapeCoverIsFittedOverABlurredBackground`, `MetadataSheetTests/testChooseImageAndResetCoverUpdateTheCardCover` → T52e
  - `MetadataSheetTests/testTagFieldSuggestionsArrowKeysAndReturn` → T52f
  - `CategoryManagerTests/testCreateRenameAssignAndDeleteACategory` → T52g (plural text)
  - `ReaderChromeTests/testOptionCommandHTogglesTheInspector` → open decision (⌥⌘H replacement)
  The tab-bar selector problem is fixed (the user's helper edits); the single-test run passes.

## Decisions waiting for the user (ask, don't decide)
- ⌥⌘H collides with macOS "Hide Others" (T52 step 35). Propose a replacement (suggestion: ⌥⌘I) and the SPEC §5 change.
- Restore reader tabs after quit and relaunch, or not (T52 step 38)?
- UX items U1–U7 in the T52 report: triage and propose; build only what the user approves.

## Next steps
1. Confirm CI on `master` is green: `./scripts/ci.sh status`.
2. Finish the T52g and T52h specs (architect), add all T52 fix tasks to the Phase 1 README, then run them through the normal loop.
3. Run ui-tester for checkpoint T52 (cloud mode: XCUITests through CI plus screenshot review). Put the Mac-only items under "Needs a Mac" in VISUAL_CHECKS.md.
4. Continue with T53 (PDF reader view).

## Session notes (local session: add anything the cloud session needs to know)
- Unit suite at T52: 355 tests passed, 0 warnings.
- The user's own edits to `StudyReaderUITests/Support/` (selector helpers) are part of the UI-test setup commit; don't revert them.
- Secrets/ was removed from git history before the first push (2026-10-26). CI gets the Google config from the GOOGLE_XCCONFIG repo secret; cloud sessions don't need it. Never read or print `Secrets/`.
- A fresh clone and CI without the GOOGLE_XCCONFIG secret build with Google export not configured; this is expected (`Config/Base.xcconfig` uses `#include?`). `scripts/check-fresh-clone.sh` deliberately doesn't copy `Secrets/`.
- Cleanup left from the manual T52 run: the document "Checkpoint Drop C" is in the user's real library (not in the in-memory test library).
