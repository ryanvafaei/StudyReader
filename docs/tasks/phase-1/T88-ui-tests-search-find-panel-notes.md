# T88: UI tests (reliable subset, part 1): global search, PDF find bar, reader panel, Notes tab

- **Phase:** 1 (end-of-phase backlog pass, `docs/BACKLOG.md` B17 / OB6 / B27 (3)(5) / B24 (2), user decision 2026-10-28: build the reliable subset only)
- **Agent:** ui-builder
- **Depends on:** T84 (fresh settings per launch, deterministic seed, `StudyReaderUI.hasKeyboardFocus(_:)`), T85 (selection survives a search, asserted in S1), T86 (note headings in the Notes preview, asserted in C18), T87 (order only)
- **ADRs:** ADR-0011 (in-memory launches), ADR-0019 (XCUITests), ADR-0020 (CI)
- **Visual check needed:** no (these are the checks)
- **UI tests:** YES. This task may run its own targeted UI tests (criterion 12), max 2 attempts, never in parallel with another CI job.

## Goal
Add CI-reliable XCUITests for the T63/T69 coverage proposals the user picked:
- search S1, S3, S4 (`docs/checkpoints/T69-cloud-2026-10-28.md`, "Coverage");
- find bar F1–F3 (same report);
- reader panel C3, C6 and Notes tab C17, C18 (`docs/checkpoints/T63-cloud-2026-10-27.md`, "Proposed XCUITests").

Each test also checks the related backlog-pass fix: B22 (1) via T85 in S1, Shift-Return (B24 2) in F2, and note headings via T86 in C18.

No pixel scans, no drags, no dark mode: those stay on the Mac list.

## Files to touch
- `StudyReader/Features/Search/SearchResultsView.swift` (modify: three accessibility identifiers, nothing else)
- `StudyReaderUITests/Support/StudyReaderUI+SearchAndReader.swift` (new: helpers below; don't edit the user's existing `Support/` files)
- `StudyReaderUITests/GlobalSearchTests.swift`, `FindInDocumentTests.swift`, `HighlightsPanelTests.swift`, `NotesTabTests.swift` (new)

## Interfaces to produce
```swift
// SearchResultsView: on the three hit Buttons (document, highlight, note), after .buttonStyle(.plain)
.accessibilityIdentifier("search-hit-document")   // DocumentHit rows
.accessibilityIdentifier("search-hit-highlight")  // HighlightHit rows
.accessibilityIdentifier("search-hit-note")       // NoteHit rows

// StudyReaderUITests/Support/StudyReaderUI+SearchAndReader.swift
extension StudyReaderUI {
    var searchField: XCUIElement { app.searchFields.firstMatch }
    /// kind: "document", "highlight" or "note".
    func searchHits(_ kind: String) -> XCUIElementQuery   // app.descendants(matching: .any).matching(identifier: "search-hit-\(kind)")
    var pageField: XCUIElement { app.textFields["Page number"] }
    var pageNumber: String                                 // pageField.value as? String ?? ""
    var findField: XCUIElement { app.textFields["Find in document"] }
    var matchCountText: String                             // text(of:) the static text labelled "Match count"
    /// Static text whose label or value equals `text`.
    func staticText(_ text: String) -> XCUIElement
    /// Static text whose label or value begins with / contains `text`.
    func staticText(beginningWith text: String) -> XCUIElement
    func staticText(containing text: String) -> XCUIElement
    /// Selects all text in the focused search field and deletes it.
    func clearSearchField()
}
```

## Rules for every test (CI reliability)
- Follow the existing class pattern: `final class …: XCTestCase`, `continueAfterFailure = true` in `setUpWithError`, and `@MainActor` on every test and helper (no Swift 6 isolation warnings; B35 3).
- Use the seeded library (`StudyReaderUI.launch()`). Seed facts you can rely on, from `SampleLibrary.swift`:
  - Lecture PDF: 3 pages, highlights on p. 1, 2 and 3; the p. 2 highlight is "Cristae increase the inner membrane surface area." with note "Check this for the quiz".
  - "proteins" appears on p. 1 ("Proteins embedded …") and twice on p. 3.
  - Gradient Descent Markdown: 4 highlights; its text contains "Stochastic".
  - Sparse Attention PDF: no highlights.
- Wait with `waitForExistence` / `ui.waitUntil` (5–10 s). Never use a bare `sleep` other than `ui.settle`.
- Attach `ui.attachHierarchy` once in the first test of each new class (selectors on macOS differ: read the dump before attempt 2). Attach a screenshot at each screen the checkpoint reports said had none: search results, find bar, Notes preview.
- No pixel scans (`ScreenPixels`), no coordinate drags, no appearance launch arguments.
- **Constraint (standing rule, HANDOFF.md):** Return and Escape in the library search field must not open or clear the library selection. S1 must not weaken this. `LibraryOpenTests` runs in the same targeted run.

## What to do
1. **Identifiers** in `SearchResultsView` as above (the only product change; behaviour unchanged).
2. **Helpers** in the new Support file, using the existing `text(of:)` and predicate style (`label == %@ OR value == %@`, `BEGINSWITH`, `CONTAINS`).
3. **`GlobalSearchTests`** (T66, SPEC F-12):
   - **S1 `testTypingAQueryShowsGroupedResultsAndClearingRestoresTheSelection`:**
     - Click the Lecture card and assert `card.isSelected`.
     - ⌘F, then `searchField` exists. Type "membrane". A static text beginning with "Documents (" and one beginning with "Highlights (" appear, and some `search-hit-document` has a label containing "p. ". Screenshot "Search results".
     - Replace the query with "Stochastic": some `search-hit-document` label contains "Section".
     - Replace it with "zzqxv": `No results for "zzqxv"` appears.
     - `clearSearchField()`: the Lecture card is back and `isSelected` (B22 1, T85).
     - If `isSelected` doesn't reflect the card's `.isSelected` trait, read the hierarchy dump and use the attribute it shows. Report it.
   - **S3 `testClickingAHitOpensTheReaderAtTheLocation`:**
     - ⌘F, type "Cristae", click the first `search-hit-highlight`. A tab `Sample.lecture` opens and `pageNumber == "2"` (wait 8 s).
     - Click `ui.tab(at: 0)` (library), replace the query with "Stochastic" and click the first `search-hit-document`. A tab `Sample.gradient` opens.
   - **S4 `testCommandShiftFFromAReaderShowsTheLibrarySearch`:** `ui.openDocument(Sample.lecture)`, then ⇧⌘F. Within 5 s: `selectedTabTitle != Sample.lecture`, `searchField.exists`, `sidebar.isHittable`. Don't assert keyboard focus (B22 2 stays a Mac check).
4. **`FindInDocumentTests`** (T67, SPEC F-04 find). Each test opens the Lecture PDF and waits for the toolbar button "Find in Document" (10 s).
   - **F1 `testPDFFindBarOpensFromShortcutToolbarAndMenu`:** ⌘F shows `findField`. Escape hides it (`waitForNonExistence`, 5 s). The toolbar "Find in Document" shows it, and the button "Close find bar" hides it. `ui.menu("Edit", "Find in Document")` shows it. Screenshot "PDF find bar".
   - **F2 `testPDFFindCountsAndSteps`** (also B24 2):
     - ⌘F, type "proteins". Wait until `matchCountText` matches `^(\d+) of (\d+)$` with N ≥ 2, and read k and N. Don't assume k = 1: the first match follows the restored page.
     - Return gives `"\(k % N + 1) of \(N)"`. Shift-Return (`typeKey(.return, modifierFlags: .shift)`) gives `"\(k) of \(N)"` again.
     - Pressing Return N times comes back to `"\(k) of \(N)"` (wrap).
   - **F3 `testPDFFindWithNoMatchesDisablesTheArrows`:** type "zzqxv". `matchCountText == "No matches"`, and the buttons "Previous match" and "Next match" exist with `isEnabled == false`.
5. **`HighlightsPanelTests`** (T63, SPEC F-06):
   - **C3 `testEmptyStateWhenTheDocumentHasNoHighlights`:** open `Sample.sparse`, then `ui.showHighlightsPanel()`. The static text "No highlights yet. Select text to highlight it." appears and `highlightRows.count == 0`.
   - **C6 `testClickingARowJumpsToItsPage`:** open the Lecture PDF, `showHighlightsPanel()`, `waitForRows(3)`. Click the row whose value begins with "p. 1": `pageNumber == "1"` (8 s). Then the row whose value begins with "p. 3": `pageNumber == "3"`. Select rows by value, not by index. No band pixel check.
6. **`NotesTabTests`** (T63/T82/T86, SPEC F-09):
   - **C17 `testNotesTabKeepsTextAcrossTabSwitchAndReopen`:**
     - Open the Lecture PDF, open the inspector and click the radio "Notes". Click `app.textViews["Document note"]`, assert `ui.hasKeyboardFocus` on it, type "Remember cristae", then `settle(1.5)`.
     - Click the radio "Highlights", then "Notes": the editor's value contains "Remember cristae".
     - `closeFrontTab()`, wait for the library, open the Lecture again and show Notes: the value contains the text (wait 5 s).
   - **C18 `testPreviewRendersHeadingsListsAndTags`:**
     - In the Notes tab of the Lecture, type `"# Plan\n#todo check\n\n- a\n- b\n\n1. one\n2. two"` and tick `app.checkBoxes["Preview"]`.
     - These static texts exist: "Plan", one containing "#todo check", "• a", "• b", "1. one", "2. two". No static text equals "# Plan". Screenshot "Notes preview".
     - Untick Preview: the editor's value contains "# Plan".
     - Select all, delete, and tick Preview: "No notes yet." appears.
7. Run the targeted UI tests (criterion 12). If a test fails, read the screenshot and hierarchy dump, fix the selector or wait, and run once more.
   - If a test still fails after attempt 2, stop and report the test, the failure line, the screenshot name and your diagnosis (selector problem or product bug).
   - Never weaken an assertion, delete a test or add `XCTSkip` to make the run green.
   - Report a product bug; don't fix it here.

## Acceptance criteria
1. `GlobalSearchTests/testTypingAQueryShowsGroupedResultsAndClearingRestoresTheSelection` passes (includes the B22 1 selection check).
2. `GlobalSearchTests/testClickingAHitOpensTheReaderAtTheLocation` passes.
3. `GlobalSearchTests/testCommandShiftFFromAReaderShowsTheLibrarySearch` passes.
4. `FindInDocumentTests/testPDFFindBarOpensFromShortcutToolbarAndMenu` passes.
5. `FindInDocumentTests/testPDFFindCountsAndSteps` passes (proves Shift-Return goes back: B24 2).
6. `FindInDocumentTests/testPDFFindWithNoMatchesDisablesTheArrows` passes.
7. `HighlightsPanelTests/testEmptyStateWhenTheDocumentHasNoHighlights` and `HighlightsPanelTests/testClickingARowJumpsToItsPage` pass.
8. `NotesTabTests/testNotesTabKeepsTextAcrossTabSwitchAndReopen` and `NotesTabTests/testPreviewRendersHeadingsListsAndTags` pass.
9. `LibraryOpenTests` still passes (the search-field Return/Escape guard).
10. No Swift 6 isolation warnings from the new files in the UI-test compile (quote the warning lines of `build/ci/<run>/uitest.log`, or "none").
11. `./scripts/build.sh` succeeds. Reviewer check: the only product diff is the three identifiers; no `ScreenPixels`, `press(forDuration:thenDragTo:)` or `-AppleInterfaceStyle` in the new tests.
12. **This task may run its own targeted UI tests**, max 2 attempts, never two CI jobs at once: `./scripts/ci.sh uitest StudyReaderUITests/GlobalSearchTests StudyReaderUITests/FindInDocumentTests StudyReaderUITests/HighlightsPanelTests StudyReaderUITests/NotesTabTests StudyReaderUITests/LibraryOpenTests`. Report the run URL, the pass/fail list and which VISUAL_CHECKS "Needs a Mac" steps the new tests now cover (the orchestrator updates VISUAL_CHECKS.md).

## Out of scope
S2 and S5, F4 and F5 (Markdown find bar), C0–C2, C4–C5, C7–C16 and C19 (pixel, drag, popover and dark-mode tests stay on the Mac list), the browser and Google tests (T89), the B23 mutation run, any product change beyond the three identifiers.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
2026-10-28, implementer ui-builder Sonnet medium (no reworks; 2 UI attempts plus 1 extra user-approved targeted run), reviewer code-reviewer Sonnet medium: APPROVED; CI evidence: UI run 40711023791 (F1, F2, F3, C3, C6, C17, S3, S4 + 11 LibraryOpenTests; it ran after the PDFFindBar accessibilityValue build 40710460066) and 40714957031 (C18 pass after the label-or-value selector fix; S1 still failed). S1 (grouped search results) removed by user decision and moved to VISUAL_CHECKS Needs a Mac; PDFFindBar .accessibilityValue(status) accepted as a one-line a11y fix beyond the "three identifiers only" scope
