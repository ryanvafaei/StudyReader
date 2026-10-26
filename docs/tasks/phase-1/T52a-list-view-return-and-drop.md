# T52a: List view opens on Return and accepts dropped files

- **Phase:** 1 (T52 checkpoint fix; SPEC F-01 AC4 open from the library, F-02 import by drop)
- **Agent:** ui-builder
- **Depends on:** T52
- **ADRs:** docs/decisions/0017-reader-windows-and-commands.md, docs/decisions/0019-ui-checks-xcuitest-and-peekaboo.md
- **Visual check needed:** yes (the drop only: real Finder drags can't be done from XCUITest; ui-tester's Peekaboo pass). Return: no (covered by UI test)

## Goal
Findings from `docs/checkpoints/T52-manual-2026-10-25.md`: step 3, Return on a selected list row does nothing (the grid already handles Return); step 40, dropping a PDF onto the list view does nothing (the grid accepts it through `RootView`'s `.dropDestination`, but the list's `NSTableView` takes the drag first).

## Files to touch
- `StudyReader/Features/Library/LibraryView.swift` (modify)

## What to do
1. **Return.** Add one private helper used by both layouts:
   ```swift
   /// Return key: opens the selected document. Ignored with nothing selected.
   private func openSelection() -> KeyPress.Result {
       guard let currentSelection else { return .ignored }
       openDocument(currentSelection)
       return .handled
   }
   ```
   The grid's `.onKeyPress(.return)` calls it. On the `Table`, add `.onKeyPress(.return) { openSelection() }`, plus `@FocusState private var isListFocused: Bool`, `.focused($isListFocused)` and `.defaultFocus($isListFocused, true)` on the table, so the table has keyboard focus after a row is clicked or the layout switches to List.
2. **Drop.** Switch the table to the rows-builder form so rows can take drops, and keep the columns and the context menu as they are:
   ```swift
   Table(of: LibraryItem.self, selection: tableSelection) {
       // the existing TableColumns, unchanged
   } rows: {
       ForEach(model.visibleItems) { item in
           TableRow(item)
       }
       .dropDestination(for: URL.self) { _, urls in
           session.importCoordinator.importURLs(urls)
       }
   }
   ```
   The insertion index is ignored: a drop anywhere on the list (on a row, between rows or below the last row) imports, like a drop on the grid. `RootView`'s drop handling stays as it is for the rest of the window.

## Acceptance criteria
1. Return on a selected list row opens it as a reader tab → UI test `StudyReaderUITests/LibraryOpenTests/testListViewReturnOpensTheSelectedRow` (step 3 of the T52 report) turns green.
2. These keep passing: `LibraryOpenTests/testReturnOpensTheSelectedCardAndDoesNothingWithoutSelection` (grid Return, step 2), `testListViewDoubleClickOpens`, `testListViewContextMenuOpenOpens` (step 3).
3. `./scripts/build.sh` succeeds and `./scripts/test.sh` stays green (no unit test changes: this is view wiring only).
4. Visual check (ui-tester, Peekaboo, `./scripts/run-app.sh`): seed the sample library, switch to List, drag a PDF from Finder onto a row, then another onto the empty area below the last row: each import finishes and the new document appears in the list (step 40 of the T52 report). A drop on the grid still imports.

The implementer doesn't run `./scripts/uitest.sh` (only ui-tester controls the screen, CLAUDE.md); ui-tester runs the named UI tests during review. The UI test names may have shifted slightly while the UI-test target was being made to compile; if so, use the test in `LibraryOpenTests.swift` covering step 3.

## Out of scope
Clearing a grid selection (U3), the drop overlay for the list, changes to `RootView` or `ImportCoordinator`.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
