# T89: UI tests (reliable subset, part 2): Highlights browser and the unconfigured Google export

- **Phase:** 1 (end-of-phase backlog pass, `docs/BACKLOG.md` B17 / B27 (3)(5) / B35 (4), user decision 2026-10-28: build the reliable subset only)
- **Agent:** ui-builder
- **Depends on:** T88 (order only; never two UI-test CI runs at once), T83 (`isExporting`, Settings Google spinner), T84 (deterministic seed, `hasKeyboardFocus` helper)
- **ADRs:** ADR-0011, ADR-0018 (not-configured state), ADR-0019, ADR-0020
- **Visual check needed:** no (these are the checks)
- **UI tests:** YES. This task may run its own targeted UI tests (criterion 10), max 2 attempts, never in parallel with another CI job.

## Goal
Add CI-reliable XCUITests for the Highlights browser proposals the user picked: H1, H2, H4, H5, H6 and H9 from `docs/checkpoints/T69-cloud-2026-10-28.md` ("Extend `HighlightsBrowserTests`"). Also add the two unconfigured-Google tests from `docs/checkpoints/T74-cloud-2026-10-28.md` ("Coverage"): the Settings > Google tab and the "Export Selection…" not-configured alert.

No pixel scans, no drags, no dark mode, no date pickers.

## Files to touch
- `StudyReaderUITests/HighlightsBrowserTests.swift` (modify: add tests and small private helpers; keep the existing tests unchanged)
- `StudyReaderUITests/SettingsTests.swift` (modify: add one test)

No product code changes.

## Seed facts (from `SampleLibrary.swift`, 10 highlights)
| Document (title in the Document menu) | Category | View | Highlights (colour, page, note) |
|---|---|---|---|
| `Sample · Lecture 1: Cell Biology` | Lecture slides | PDF | yellow p. 1; green p. 2 "Check this for the quiz"; blue p. 3 |
| `Sample · Notes: Gradient Descent` | Notes | Markdown | yellow; green "Diverges"; blue; pink |
| `Sample · Book chapter: Probability` | Book chapter | PDF | pink p. 1 |
| `Sample · Lab manual: Pendulum` | Other | PDF | purple p. 1 |
| `Sample · Slides: Membrane Transport` | Lecture slides | PDF | yellow p. 2 |

Totals:
- by colour: yellow 3, green 2, blue 2, pink 2, purple 1;
- by note: with note 2, without note 8;
- by view: Markdown 4;
- by category: Notes 4.

No seeded highlight has a tag. The count text in the filter bar is "N highlights" / "1 highlight" (plural catalog entry).

## Rules for every test (CI reliability)
- Same class pattern and `@MainActor` rule as the existing tests. Start each test with `StudyReaderUI.launch()` and `ui.showSection("Highlights")`, then wait for the count text "10 highlights" (8 s) before acting.
- Rows: the existing `rows(in:)` (identifier "highlight-row"), sorted by `frame.minY`. A row's value is "<document title>, p. N, <Colour>" (no page for Markdown). Select rows by value (`CONTAINS`), not by position, when the document or page matters.
- Multi-select: `XCUIElement.perform(withKeyModifiers: .command) { row.click() }` and `.shift` likewise. Settle 0.5 s after each click.
- Filter controls: `ui.app.descendants(matching: .any)["Filter by document"].firstMatch` (also "Filter by category", "Filter by note", "Filter by view"), then `ui.app.menuItems[title]`. Colour toggles are buttons "Filter by Yellow" etc.; Clear is the button "Clear filters" (`.firstMatch`).
- The count text: a static text whose label or value equals the expected string (add a private `countText(_ ui:, _ text: String) -> XCUIElement`).
- Attach `ui.attachHierarchy` in the first new test (bulk bar and popovers were never dumped). Attach screenshots of the bulk bar, the delete confirmation, the export alert and Settings > Google (none exist yet; B27 3).
- No pixel scans, coordinate drags, date pickers or appearance arguments.
- **Constraint (standing rule, HANDOFF.md):** Return and Escape in the bulk bar's "Tag name" field must stay in that field: no window opens and nothing else changes (H5 checks this).

## What to do
1. **H1 `testCountTextSingularAndPlural`:** "10 highlights". Click "Filter by Purple": "1 highlight" and exactly 1 row. Clear: "10 highlights".
2. **H2 `testDocumentCategoryNoteViewAndColourFiltersNarrow`** (after each step, Clear and expect "10 highlights" again):
   - Document `Sample · Lecture 1: Cell Biology` → "3 highlights".
   - Category "Notes" → "4 highlights".
   - Note "With note" → "2 highlights", then Note "Without note" → "8 highlights".
   - View "Markdown" → "4 highlights".
   - Yellow and Pink together → "5 highlights".
   Screenshot after the Category step.
3. **H4 `testCommandAndShiftClickSelectSeveralRowsAndShowTheBulkBar`:**
   - Click row 0, then ⌘-click row 1. The element labelled "Selected" has value "2"; the static text "2 highlights selected" appears in the detail pane; the buttons "Add tag to selection", "Remove tag from selection", "Change color of selection", "Export selection" and "Delete selection" exist. Screenshot "Bulk bar".
   - Click row 0, then ⇧-click row 2: "Selected" has value "3".
4. **H5 `testBulkAddAndRemoveTag`:**
   - Select rows 0 and 1, then click "Add tag to selection". `app.textFields["Tag name"]` appears and has keyboard focus (`ui.hasKeyboardFocus`). Type "uitag" and press Return.
   - The window count is unchanged, the Lecture library card doesn't appear, and the list still has its rows.
   - Open "Filter by tag": the menu item "uitag" exists. Click it: "2 highlights".
   - Select both rows, open "Remove tag from selection" and click "uitag": the empty state "No highlights match these filters" appears (8 s). Clear.
   - Escape case: select two rows, open "Add tag to selection", press Escape. The popover closes (`textFields["Tag name"]` gone), "Selected" still has value "2", and no tag is added.
5. **H6 `testBulkColourAndDeleteWithConfirmation`:**
   - Filter Yellow ("3 highlights"). Select rows 0 and 1, open "Change color of selection" and click the menu item "Blue": "1 highlight" (the two rows left the Yellow filter). Clear.
   - Filter Blue: "4 highlights". Select rows 0 and 1 and click "Delete selection". The static text "Delete 2 highlights?" appears; screenshot "Delete confirmation". `ui.alertButton("Cancel")`: still "4 highlights". Repeat and `ui.confirmDelete()`: "2 highlights".
   - Singular: right-click row 0 and click the menu item "Delete…". "Delete 1 highlight?" appears. Cancel: "2 highlights".
6. **H9 `testOpenInDocumentFromButtonContextMenuAndDoubleClick`:**
   - Filter Document Lecture, click the row whose value contains "p. 3", then click the button "Open in Document". A tab `Sample.lecture` opens and `app.textFields["Page number"]` has the value "3" (8 s).
   - Click `ui.tab(at: 0)`. Clear and filter Document Gradient Descent. Right-click row 0 and click the menu item "Open in Document": a tab `Sample.gradient` opens.
   - Click `ui.tab(at: 0)` again and double-click a Gradient row. The tab count is unchanged and `selectedTabTitle == Sample.gradient` (the open tab is selected, not duplicated).
7. **`testExportSelectionShowsTheNotConfiguredAlert`** (T73, unconfigured CI build):
   - Select rows 0 and 1 and click "Export selection". An alert shows the text "Google export not configured." (label or value; 5 s); screenshot "Export selection alert".
   - `ui.alertButton("OK")` closes it. "Selected" still has value "2" and the count is still "10 highlights".
8. **`SettingsTests/testGoogleTabShowsNotConfiguredAndHidesFolderAndTargets`** (T72/T73):
   - `launch(seed: false)`, ⌘,, find the Settings window as the existing test does, then click `window.toolbars.buttons["Google"]`.
   - `window.staticTexts["Google export not configured"]` exists (8 s; T83 may show a spinner first).
   - Neither `window.textFields["Export folder link"]` nor `window.descendants(matching: .any)["Export targets"]` exists. Screenshot "Settings Google unconfigured".
   - ⌘W.
9. Run the targeted UI tests (criterion 10). The same failure rules as T88 apply:
   - one fix attempt after reading the screenshot and hierarchy;
   - after attempt 2, stop and report the test, the failure line, the screenshot and your diagnosis;
   - never weaken an assertion, delete a test or add `XCTSkip`;
   - report product bugs, don't fix them.

## Acceptance criteria
1. `HighlightsBrowserTests/testCountTextSingularAndPlural` passes.
2. `HighlightsBrowserTests/testDocumentCategoryNoteViewAndColourFiltersNarrow` passes.
3. `HighlightsBrowserTests/testCommandAndShiftClickSelectSeveralRowsAndShowTheBulkBar` passes.
4. `HighlightsBrowserTests/testBulkAddAndRemoveTag` passes (includes the Return/Escape rule in the Tag name field).
5. `HighlightsBrowserTests/testBulkColourAndDeleteWithConfirmation` passes (plural and singular titles).
6. `HighlightsBrowserTests/testOpenInDocumentFromButtonContextMenuAndDoubleClick` passes.
7. `HighlightsBrowserTests/testExportSelectionShowsTheNotConfiguredAlert` and `SettingsTests/testGoogleTabShowsNotConfiguredAndHidesFolderAndTargets` pass.
8. The existing `HighlightsBrowserTests` and `SettingsTests` tests (including T84's `testSettingsOpensWithoutAFocusedLabelField`) still pass. No Swift 6 isolation warnings from these two files (quote `uitest.log` or "none").
9. `./scripts/build.sh` succeeds. Reviewer check: no product file in the diff; no `ScreenPixels`, coordinate drag or appearance argument in the new tests.
10. **This task may run its own targeted UI tests**, max 2 attempts, never two CI jobs at once: `./scripts/ci.sh uitest StudyReaderUITests/HighlightsBrowserTests StudyReaderUITests/SettingsTests`. Report the run URL, the pass/fail list and which VISUAL_CHECKS "Needs a Mac" steps the new tests now cover.

## Out of scope
H0 (exists), H3 (sort), H7 (detail edits), H8 (snapshot thumbnail), the date range filter and the Tag Any/All mode (no seeded highlight tags), the Export sheet picker and width tests and the File-menu enabled-state test from the T74 report, real Google export or sign-in, any product change.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
2026-10-28, implementer ui-builder Sonnet medium (no reworks; 2 targeted UI runs, one per class), reviewer code-reviewer Sonnet medium: APPROVED; CI evidence: HighlightsBrowserTests 13 tests, 0 failures (run 40717065767), SettingsTests 3 tests, 0 failures (run 40719065646); UI-test code only, no product change; minor follow-ups in BACKLOG
