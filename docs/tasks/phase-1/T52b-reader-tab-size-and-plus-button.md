# T52b: Reader tabs keep the window size; the tab bar "+" adds no empty tab

- **Phase:** 1 (T52 checkpoint fix; SPEC F-01 AC4 document tabs)
- **Agent:** ui-builder
- **Depends on:** T52
- **ADRs:** docs/decisions/0017-reader-windows-and-commands.md (native window tabs only, no custom tab bar), docs/decisions/0019-ui-checks-xcuitest-and-peekaboo.md
- **Visual check needed:** yes (F2 only: no UI test covers the tab bar "+"; ui-tester's Peekaboo pass). F1: no (covered by UI test)

## Goal
Findings F1 and F2 in `docs/checkpoints/T52-manual-2026-10-25.md`:
- **F1.** With the library window filling the screen, opening a reader tab resized the whole tab group to the reader window's default size (900 × 486), and the library kept that size after the tab closed. Likely causes: the reader `WindowGroup` has no `defaultSize`, so its window starts at a content-derived size, and `ReaderTabbing.joinMainTabGroup` adds it to the group synchronously from `viewDidMoveToWindow` (during SwiftUI's first layout of that window), so its frame wins over the group's.
- **F2.** The tab bar's "+" button opens a reader window with a nil document ID: an empty tab titled "StudyReader" that says "No document".

## Files to touch
- `StudyReader/App/ReaderTabbing.swift` (modify)
- `StudyReader/Features/Reader/ReaderWindowView.swift` (modify `ReaderWindowRoot` only)
- `StudyReader/App/StudyReaderApp.swift` (modify: reader `WindowGroup`)

## What to do
1. `StudyReaderApp`: give the reader `WindowGroup` `.defaultSize(width: 1100, height: 720)` (same as the main window). Don't add restoration modifiers (tab restore after quit awaits a user decision).
2. `ReaderTabbing.joinMainTabGroup(_:)`: keep `configure(window)` synchronous (with `.preferred` and the shared identifier AppKit may already tab the window in). Read `let groupFrame = anchor.frame`, call `window.setFrame(groupFrame, display: false)`, then do the rest on the next main-actor turn (`Task { @MainActor in … }`): if the window isn't in the anchor's group yet, `addTabbedWindow(_:ordered: .above)` after the group's last window as today; then, if `window.frame != groupFrame`, `window.setFrame(groupFrame, display: true)`; then `window.makeKeyAndOrderFront(nil)`. The deferral also keeps AppKit from re-laying out the window while SwiftUI is laying it out (see T52h).
3. Add to `ReaderTabbing`:
   ```swift
   /// A reader window without a document (the tab bar's "+", or restoration without a value) is closed on the
   /// next main-actor turn and the library tab is brought forward. No empty "No document" tab stays open.
   static func discardEmptyWindow(_ window: NSWindow)
   ```
   It closes `window` and calls `mainWindow?.makeKeyAndOrderFront(nil)`.
4. `ReaderWindowRoot`: in the `WindowAccessor` callback, call `ReaderTabbing.discardEmptyWindow(hostWindow)` when `documentId == nil`, otherwise `joinMainTabGroup(hostWindow)` as now. Keep the "No document" placeholder view (it shows for at most one turn).

## Acceptance criteria
1. Opening a reader tab doesn't change the window's size, and the library keeps its size after the tab closes → UI test `StudyReaderUITests/LibraryOpenTests/testOpeningAReaderTabKeepsTheWindowSize` (finding F1) turns green.
2. Tabbing still works → `LibraryOpenTests/testDoubleClickOpensReaderAsTabInLibraryWindow` (step 1), `testReopeningAnOpenDocumentSelectsItsTab` (step 4), `testTabMovesToItsOwnWindowAndMergesBack` (step 5) keep passing.
3. `ReaderTabbingTests/configureSetsPreferredTabbing` and `ReaderTabbingTests/joinConfiguresEvenWithoutGroup` keep passing (`./scripts/test.sh StudyReaderTests/ReaderTabbingTests`); `./scripts/build.sh` succeeds.
4. Visual check (ui-tester, Peekaboo, `./scripts/run-app.sh`): seed, open a document so the tab bar shows, click the tab bar's "+": no "No document" tab stays; the library tab is selected and the tab count is unchanged (finding F2).

The implementer doesn't run `./scripts/uitest.sh` (CLAUDE.md); ui-tester runs the named UI tests during review. If a test name has shifted, use the test in `LibraryOpenTests.swift` covering finding F1.

## Out of scope
Removing the "+" button itself (AppKit shows it for SwiftUI `WindowGroup` windows), tab restore after quit, a custom tab bar, any change to `ReaderRouter`.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-26, code-reviewer sonnet high: CHANGES REQUESTED (1st): ReaderTabbing restores a stale preReaderLibraryFrame captured at first join, reverting user resizes/moves made while reading, and fires for a reader moved to its own window; doc comment contradicts code. Test change (settle) judged not a weakening.
- 2026-10-26, code-reviewer sonnet high (escalated): APPROVED (2nd). Stale-frame issue resolved: the stored library frame is kept current on live resize and mouse-driven moves; the membership check was replaced by 'no windows other than library and closing' because AppKit has already removed the closing tab at willClose (CI run 40408688957). Test change (settle) is not a weakening. Known gaps, on the Needs-a-Mac list: zoom while reading may be reverted at close; full screen untested. Spec's fix alone wasn't enough for AC1, hence the restore-on-close addition.
- 2026-10-27, implementer record (backfill): ui-builder, Haiku per agent file (.claude/agents/ui-builder.md; model not verified at run time), effort medium; reworks: 2, both at effort high, as noted in the lines above.
