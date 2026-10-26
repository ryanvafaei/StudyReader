# Handoff: local Mac session → cloud session (2026-10-26)

Read this first in a new cloud session, then CLAUDE.md, ADR-0019 and ADR-0020. The local Claude Code session on the Mac updates this file before handing over; keep it current at each phase or checkpoint change.

## Where the project is
- Phase 1 (study loop). T29–T52 are committed. T52 was the first visual checkpoint.
- T52 checkpoint, manual run: `docs/checkpoints/T52-manual-2026-10-25.md`. Step 1 passed: reader tabs join the library window, so the reader work isn't blocked.
- Fix specs written: T52a–T52f in `docs/tasks/phase-1/` (not yet in the Phase 1 README). Still to write: T52g (category-delete plural text: "Its 1 document moves to Other.", step 24) and T52h (`Picker: the selection ""` console warnings plus the two layout warnings, step 39). See the report for both.
- UI tests (`StudyReaderUITests/`, ADR-0019) compile and launch the app with the sample library. Failing tests that match known T52 findings must stay failing until their fix task: never weaken them. Current state (2026-10-26): the full suite has not been run yet. `LibraryOpenTests/testDoubleClickOpensReaderAsTabInLibraryWindow` fails with `tabs: []` although the screenshot shows the tab bar ("Library" and the reader tab), so `tabBar`/`tabTitles` in `Support/StudyReaderUI.swift` use the wrong selector. A ui-builder run to fix selectors (StudyReaderUITests/ only) was stopped by the user and not resumed. The user already changed the card, row, category-row and tag-count helpers to match label OR value (macOS exposes static text as `value`).

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
- `Secrets/Google.xcconfig` is tracked in git (commit 55cc1c9 "google credentials") although `Secrets/` is in `.gitignore`. Nothing was pushed until the user decides what to do about it (see the GitHub setup step in the session). Never read or print `Secrets/`.
- Cleanup left from the manual T52 run: the document "Checkpoint Drop C" is in the user's real library (not in the in-memory test library).
