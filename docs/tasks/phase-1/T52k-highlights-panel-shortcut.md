# T52k: Highlights panel shortcut ⌥⌘H → ⌥⌘I

- **Phase:** 1 (T52 checkpoint fix; SPEC F-06 document highlights panel, §5 keyboard shortcuts)
- **Agent:** ui-builder
- **Depends on:** T52
- **ADRs:** docs/decisions/0017-reader-windows-and-commands.md, docs/decisions/0019-ui-checks-xcuitest-and-peekaboo.md
- **Visual check needed:** no (covered by UI test)

## Goal
Step 35 of `docs/checkpoints/T52-manual-2026-10-25.md` (and the cloud run of 2026-10-27): ⌥⌘H runs the system's StudyReader > Hide Others instead of toggling the reader's right panel. User decision 2026-10-27: the Highlights panel shortcut becomes **⌥⌘I**. SPEC §5 and F-06, the T52 and T63 specs are already updated (architect); this task changes the code and the UI test.

## Files to touch
- `StudyReader/App/AppCommands.swift` (modify: one line, View > Highlights Panel)
- `StudyReader/Features/Reader/ReaderModel.swift` (modify: one doc comment, `toggleRightPanel(tab:)`)
- `StudyReaderUITests/ReaderChromeTests.swift` (modify: rename and update one test)

## What to do
1. `AppCommands`, `CommandGroup(after: .sidebar)`, button "Highlights Panel": replace `.keyboardShortcut("h", modifiers: [.command, .option])` with `.keyboardShortcut("i", modifiers: [.command, .option])`. Change nothing else in the file (the action and `.disabled(readerActions == nil)` stay).
2. `ReaderModel.toggleRightPanel(tab:)` doc comment: "Shows or hides the right panel on `tab`: the toolbar toggle and ⌥⌘I (View > Highlights Panel) both use it." No code change.
3. `ReaderChromeTests`: rename `testOptionCommandHTogglesTheInspector` to `testOptionCommandITogglesTheInspector` and replace its body and doc comment with:
   ```swift
   /// Step 35. ⌥⌘I toggles the inspector both ways. At the T52 checkpoint the shortcut was ⌥⌘H, which ran the
   /// system's "Hide Others" instead (user decision 2026-10-27: ⌥⌘I).
   @MainActor
   func testOptionCommandITogglesTheInspector() {
       let ui = openReader()
       ui.app.typeKey("i", modifierFlags: [.command, .option])
       XCTAssertTrue(ui.waitUntil(timeout: 3) { ui.isInspectorOpen }, "⌥⌘I didn't open the inspector.")
       XCTAssertEqual(ui.app.state, .runningForeground, "⌥⌘I sent StudyReader to the background.")
       ui.app.typeKey("i", modifierFlags: [.command, .option])
       XCTAssertTrue(ui.waitUntil(timeout: 3) { !ui.isInspectorOpen }, "A second ⌥⌘I didn't close the inspector.")
   }
   ```
   The "Show All" clean-up of the old test goes away: ⌥⌘I hides nothing. Don't add a `settle`, retry or `XCTSkip`; if the test fails on CI, report it, don't loosen it.
4. Grep the Swift sources and tests for any other `"h", modifiers: [.command, .option]`, `⌥⌘H` or `⌘⌥H`; no binding or claim that ⌥⌘H toggles the panel may remain (the history mention in the new test's doc comment is fine). Don't touch `docs/checkpoints/` (history).

## Acceptance criteria
1. ⌥⌘I opens and then closes the right panel in a reader tab, and the app stays in front → UI test `StudyReaderUITests/ReaderChromeTests/testOptionCommandITogglesTheInspector` passes (ui-tester runs it during review: `./scripts/uitest.sh StudyReaderUITests/ReaderChromeTests/testOptionCommandITogglesTheInspector`).
2. These keep passing: `ReaderChromeTests/testInspectorToggleShowsHighlightsAndNotesTabs` (toolbar toggle), `testViewMenuReaderItemsAreDisabledNotMissing`.
3. No `testOptionCommandHTogglesTheInspector` remains, and no Swift file binds ⌥⌘H → reviewer greps.
4. `./scripts/build.sh` succeeds and `./scripts/test.sh` stays green (no unit test changes).

The implementer doesn't run `./scripts/uitest.sh` (CLAUDE.md); ui-tester runs the named UI test during review.

## Out of scope
Other shortcuts, the panel content (T63), the inspector's behaviour for failed loads (T53, U7), the ui-tester's own notes.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
- 2026-10-27, implementer ui-builder Haiku (per agent file) medium (no reworks), reviewer code-reviewer Sonnet medium: APPROVED. ⌥⌘I toggles the inspector both ways and the app stays in front; the three named UI tests pass on CI (run 40508785508).
