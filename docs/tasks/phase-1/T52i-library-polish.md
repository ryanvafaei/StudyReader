# T52i: Library polish: selection can be cleared, covers distinct from the selection, cover edge, no focus ring

- **Phase:** 1 (T52 checkpoint fix; SPEC F-01 library grid and list, F-11 covers, §4 accessibility)
- **Agent:** ui-builder
- **Depends on:** T52, T52a (the hidden "Open Selected Document" button), T52e (`DocumentCoverView` layout)
- **ADRs:** docs/decisions/0019-ui-checks-xcuitest-and-peekaboo.md
- **Visual check needed:** yes, Mac only (dark appearance of covers, selection and cover edge; focus ring with Full Keyboard Access on). Light appearance is covered by the UI tests below.

## Goal
Items from `docs/checkpoints/T52-manual-2026-10-25.md` (U1, U3, U4) and `docs/checkpoints/T52-cloud-2026-10-27.md` (S2, S3), triaged by the user on 2026-10-27:
- **U1**: a stray blue vertical line at the library content's left edge (a clipped focus ring). It was seen at `68d636c`, when the grid was `.focusable()`; T52a removed that, so it may already be gone. This task makes sure nothing invisible in the library can take focus and locks it in with a test.
- **U3**: a grid selection can't be cleared. Clicking empty space in the grid, or pressing Escape, must clear it (Escape also in the list).
- **U4 + S2**: Markdown placeholder covers (and the extraction-failed card "Retrieval Notes", also Markdown) use `accentColor.opacity(0.15)`, almost the same light blue as the selection fill (`accentColor.opacity(0.2)`), so unselected cards look selected.
- **S3**: white first-page covers have no edge on the white window background.
- User decision: the hidden default-action button "Open Selected Document" gets `.accessibilityHidden(true)` (it catches Return window-wide and isn't a control the user should find).

## Constraint (standing rule, also in docs/HANDOFF.md)
`LibraryView`'s hidden buttons are key equivalents for the whole library window while the Library section is shown: **Return** opens the selected document (T52a) and, after this task, **Escape** clears the selection. Any task that adds a text field or search field to the library window must make Return (and Escape) typed in that field act on the field, not open the selected document or clear the selection. For example: hide `LibraryView` or disable the two buttons while the field has focus, or remove the library from the hierarchy while the field is active. Each such task needs a UI test that types Return in its field with a document selected and checks that no reader tab opens.

## Files to touch
- `StudyReader/Features/Library/LibraryView.swift` (modify: grid tap area, hidden buttons)
- `StudyReader/Features/Library/LibraryItemViews.swift` (modify: `LibraryGridCard` selection background and trait)
- `StudyReader/Features/Library/DocumentCoverView.swift` (modify: hairline edge, `GeneratedCoverView` tint and symbol)
- `StudyReaderUITests/LibraryOpenTests.swift` (modify: two new tests)
- `StudyReaderUITests/LibraryCoverTests.swift` (modify: three new tests)
- `StudyReaderUITests/MetadataSheetTests.swift` (modify: one new test)

## What to do
1. **Hidden key buttons (LibraryView).** Replace `.background { openSelectedButton }` with `.background { hiddenKeyButtons }`:
   ```swift
   /// Key equivalents for the library window (not visible, not in the accessibility tree, never focused).
   /// Return opens the selected document; Escape clears the selection. Both are disabled with no selection, so the
   /// key falls through as usual. Constraint: a text field added to the library window must keep Return and Escape
   /// for itself (see docs/HANDOFF.md).
   private var hiddenKeyButtons: some View {
       ZStack {
           Button("Open Selected Document") { openSelection() }
               .keyboardShortcut(.defaultAction)
           Button("Clear Selection") { selection = nil }
               .keyboardShortcut(.cancelAction)
       }
       .disabled(currentSelection == nil)
       .focusable(false)
       .accessibilityHidden(true)
       .opacity(0)
       .frame(width: 0, height: 0)
   }
   ```
   Keep the existing doc comment's explanation of why Return is a key equivalent (move it onto this property). Remove `openSelectedButton`.
2. **Click on empty grid space (LibraryView.grid).** Wrap the `ScrollView` in a `GeometryReader` and give the grid content a tap area that fills at least the visible height:
   ```swift
   GeometryReader { proxy in
       ScrollView {
           LazyVGrid(…) { … unchanged … }
               .padding(16)
               .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
               .contentShape(Rectangle())
               .onTapGesture { selection = nil }
       }
   }
   ```
   The cards keep their own `.onTapGesture(count: 2)` / `.onTapGesture` (child gestures win over the container's), so a click on a card still selects it and a click between or below cards clears the selection. Keep `.padding(16)` before `.frame` and `.contentShape`, so the padding is part of the tap area. Don't add `.focusable()` anywhere in the library. The list (`Table`) already clears its selection on a click below the rows; leave it.
3. **Selection look (LibraryGridCard).** Replace the background with a fill plus a 2 pt accent border, only when selected:
   ```swift
   .background {
       if isSelected {
           RoundedRectangle(cornerRadius: 10)
               .fill(Color.accentColor.opacity(0.2))
               .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 2))
       }
   }
   ```
   On the text block that already has `.accessibilityElement(children: .combine)`, add `.accessibilityAddTraits(isSelected ? .isSelected : [])` so VoiceOver reads the selection.
4. **Placeholder covers (GeneratedCoverView).** The accent colour is reserved for the selection. Tints become neutral, and the two file types differ by symbol:
   ```swift
   private var tint: Color {
       switch fileType {
       case .pdf: Color.secondary.opacity(0.2)
       case .markdown: Color.secondary.opacity(0.12)
       }
   }
   private var symbolName: String {
       switch fileType {
       case .pdf: "doc.text"
       case .markdown: "doc.plaintext"
       }
   }
   ```
   Use `Image(systemName: symbolName)`. Update the struct's doc comment: "neutral tint; the accent colour is reserved for the grid selection (U4)".
5. **Cover edge (DocumentCoverView.body).** Directly after `.clipShape(RoundedRectangle(cornerRadius: 8))`, add
   `.overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1) }`. It applies to image and generated covers alike (also in the metadata sheet preview). `separatorColor` adapts to light and dark. Add one sentence to the body's doc comment about the hairline.

## UI tests to add
Use the existing helpers in `StudyReaderUITests/Support/StudyReaderUI.swift` and `ScreenPixels.swift`; don't change the helpers. To click a screen point, use the window's coordinate: `window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x - window.frame.minX, dy: point.y - window.frame.minY)).click()` with `let window = ui.app.windows.firstMatch`. "Selected" is checked through behaviour: File > Edit Metadata… is enabled only with a selection (`ui.menuItemState("File", "Edit Metadata…").enabled`), and Return opens a tab only with a selection.

- `LibraryOpenTests/testClickOnEmptyGridSpaceClearsTheSelection`: launch, `enlargeWindow()`, click `Sample.lecture`'s card, `settle()`; assert Edit Metadata… is enabled (so the test isn't vacuous). Click the point `(cardFrame(of: Sample.lecture).maxX + 8, cardFrame(of: Sample.lecture).midY)` (the gap or padding right of the card), `settle()`; assert Edit Metadata… is disabled; type Return, wait 1 s, assert `tabTitles.isEmpty`.
- `LibraryOpenTests/testEscapeClearsTheSelectionInGridAndList`: grid: click `Sample.lecture`, `settle()`, assert enabled, type Escape, `settle()`, assert disabled; type Return, wait 1 s, `tabTitles.isEmpty`. Then `setLayout("List")`, click `row(Sample.gradient)`, `settle()`, assert enabled, Escape, `settle()`, assert disabled.
- `MetadataSheetTests/testEscapeClosesTheSheetAndKeepsTheLibrarySelection`: `openSheet(for: Sample.sparse, in: ui)`; type Escape; `sheet.waitForNonExistence(timeout: 3)`; `settle()`; Edit Metadata… is still enabled (the sheet took Escape; the library's Escape didn't run).
- `LibraryCoverTests/testPlaceholderCoversAreNeutralAndTheSelectionStandsOut`: launch, `enlargeWindow()`, wait 1 s. With nothing selected, `ScreenPixels.stats` of the top fifth of `coverRect(of: Sample.gradient)` inset by 6 pt (above the symbol): `blue - red < 0.05` (neutral; the old accent tint gave about 0.15). Strip in the card's left padding, `CGRect(x: cardFrame.minX + 1, y: cover.midY - 20, width: 5, height: 40)` for `Sample.gradient`: `blue - red < 0.05` while unselected. Click the card, `settle(0.5)`, same strip: `blue - red > 0.1` (fill and border). Attach crops of both states (`ScreenPixels.attach`) named "Placeholder unselected" and "Placeholder selected".
- `LibraryCoverTests/testWhiteCoverHasAVisibleEdge`: launch, `enlargeWindow()`, wait 1 s; `let cover = coverRect(of: Sample.sparse)` (first-page cover, white margin); strip `CGRect(x: cover.minX - 3, y: cover.midY - 20, width: 6, height: 40)` across the left edge: `luminanceRange > 0.05` (without the hairline, white cover on white background gives about 0). Attach the crop "White cover edge".
- `LibraryCoverTests/testNoFocusRingAtTheContentLeftEdge`: launch, `enlargeWindow()`, click `Sample.lecture`, `settle()`. Let `left` = the smallest `cardFrame(of:).minX` over the six sample cards and `lowest` = that card's frame. Strip from `x = ui.sidebar.frame.maxX + 1` to `left - 6`, `y` from `lowest.midY` to `lowest.maxY` (the lower half avoids the sidebar's selected row). If the strip is under 2 pt wide, `XCTFail` with the frames in the message. Assert `maxSaturation < 0.35` (a blue focus ring is far above). Attach the crop "Content left edge".

Pixel checks are heuristics in light appearance (CI); the crops are for the ui-tester's review.

## Acceptance criteria
1. Clicking empty grid space clears the selection → UI test `LibraryOpenTests/testClickOnEmptyGridSpaceClearsTheSelection` (U3).
2. Escape clears the selection in grid and list → UI test `LibraryOpenTests/testEscapeClearsTheSelectionInGridAndList` (U3).
3. Escape in the metadata sheet still closes only the sheet → UI test `MetadataSheetTests/testEscapeClosesTheSheetAndKeepsTheLibrarySelection`.
4. Placeholder covers are neutral and the selection is clearly different → UI test `LibraryCoverTests/testPlaceholderCoversAreNeutralAndTheSelectionStandsOut` (U4, S2).
5. White covers have a visible edge → UI test `LibraryCoverTests/testWhiteCoverHasAVisibleEdge` (S3).
6. No focus ring at the content's left edge → UI test `LibraryCoverTests/testNoFocusRingAtTheContentLeftEdge` (U1).
7. These keep passing: `LibraryOpenTests` (all, especially `testReturnOpensTheSelectedCardAndDoesNothingWithoutSelection`, `testListViewReturnOpensTheSelectedRow`, `testDoubleClickOpensReaderAsTabInLibraryWindow`), `LibraryCoverTests` (all), `MetadataSheetTests` (all).
8. The hidden buttons carry `.accessibilityHidden(true)` and `.focusable(false)`; no `.focusable()` in `StudyReader/Features/Library/` → reviewer reads the diff.
9. `./scripts/build.sh` succeeds and `./scripts/test.sh` stays green. No unit test changes: the selection is view state and the rest is styling.
10. Visual check (Mac, ui-tester's Peekaboo pass or the user; in a cloud session under "Needs a Mac" in VISUAL_CHECKS.md): seed the sample library; in light and dark appearance the placeholder covers (Gradient Descent, Retrieval Notes) look neutral and unselected; the selected card's fill and border stand out; white covers show a thin edge that isn't harsh in dark mode; with System Settings > Keyboard > Keyboard navigation on, press Tab through the library window: no focus ring appears on an invisible control and no blue line at the content's left edge.

The implementer doesn't run `./scripts/uitest.sh` (CLAUDE.md); ui-tester runs the named UI tests during review, with targeted runs (`./scripts/uitest.sh StudyReaderUITests/LibraryOpenTests StudyReaderUITests/LibraryCoverTests StudyReaderUITests/MetadataSheetTests`).

## Out of scope
Multi-selection, ⌘-click behaviour, keyboard arrow navigation in the grid, the list's own selection colours, tab order after merging windows (O1, open), metadata sheet changes (T52j), any new text field in the library window.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
