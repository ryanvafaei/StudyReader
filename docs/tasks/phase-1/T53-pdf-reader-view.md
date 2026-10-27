# T53: PDF reader view: display, navigation, reading position

- **Phase:** 1 (E1.2: F-04)
- **Agent:** pdf-engine
- **Depends on:** T52, T52k (both edit `AppCommands.swift`; T52k changes the Highlights Panel shortcut to ⌥⌘I)
- **ADRs:** docs/decisions/0017-reader-windows-and-commands.md, docs/decisions/0003-grdb-fts5-database-of-record.md (never write PDFs), ARCHITECTURE §3, §5.1
- **Reference:** `.references/YoPDF/macos/YoPDF/Reader/PDFViewerRepresentable.swift` (NSViewRepresentable wrapper, selection and mouse handling); `.references/reader-source/Reader/Formats/PDF/PDFKitReadingAdapter.swift` (PDFView subclass patterns). Read only these.
- **Visual check needed:** yes

## Goal
Replace T52's PDF placeholder with a PDFKit reader: continuous (default) or single-page display, zoom in/out, actual size, fit width, page thumbnails sidebar, page number field, outline, and reading position saved and restored through `ReaderModel` (F-04). Highlights and snapshots come in T56–T61; this task leaves clean extension points for them.

Also (U7 from `docs/checkpoints/T52-manual-2026-10-25.md`, approved by the user 2026-10-27): a reader that failed to load (missing original, document no longer in the library, or a PDF that PDFKit can't open) must not show the highlight-colour menu or the inspector toggle, and View > Highlights Panel (⌥⌘I) is disabled there. The chrome is shared by the PDF and Markdown readers (`ReaderTabContent`), so this one change covers both.

## Files to touch
- `StudyReader/Features/Reader/PDF/StudyPDFView.swift` (new: `PDFView` subclass)
- `StudyReader/Features/Reader/PDF/PDFReaderController.swift` (new: owns the view, registers engine actions)
- `StudyReader/Features/Reader/PDF/PDFReaderView.swift` (new: `NSViewRepresentable` + SwiftUI chrome: page field, outline popover, thumbnails)
- `StudyReader/Features/Reader/PDF/PDFOutlineItem.swift` (new)
- `StudyReader/Features/Reader/ReaderWindowView.swift` (modify: the PDF branch of `ReaderContentSlot`; U7: `ReaderTabContent`'s toolbar and inspector binding)
- `StudyReader/Features/Reader/ReaderModel.swift` (modify, U7: `isDocumentAvailable`, `engineFailed(_:)`, guard in `toggleRightPanel`)
- `StudyReader/App/AppCommands.swift` (modify, U7: the Highlights Panel item's `.disabled` only)
- `StudyReaderTests/ReaderTests/PDFReaderControllerTests.swift` (new)
- `StudyReaderTests/ReaderTests/ReaderModelTests.swift` (modify, U7: two tests)
- `StudyReaderUITests/ReaderChromeTests.swift` (modify, U7: one test)

## Interfaces to produce
```swift
@MainActor
final class StudyPDFView: PDFView {
    /// Called after mouseUp when the selection is non-empty (T59 uses it).
    var onSelectionFinished: (@MainActor (PDFSelection) -> Void)?
    /// Called for a click that doesn't start a selection; return true if handled (T59 hit-tests highlights).
    var onClick: (@MainActor (NSEvent) -> Bool)?
    /// Key handling hook for 1–5 / H (T59); return true if handled.
    var onKeyDown: (@MainActor (NSEvent) -> Bool)?
}

@MainActor
final class PDFReaderController {
    let pdfView: StudyPDFView
    private(set) var document: PDFDocument?
    init(model: ReaderModel)
    /// Opens PDFDocument(url:) on the main actor, restores model.initialPDFPosition (else page 0 top),
    /// registers ReaderEngineActions on the model, and starts position tracking.
    func load(url: URL)
    func zoomIn(); func zoomOut(); func actualSize(); func fitWidth()
    func setSinglePage(_ singlePage: Bool)
    func go(toPage index: Int)
    /// Page index + top-of-visible-area y in page space (from pdfView.currentDestination).
    func currentPosition() -> PDFPosition?
    func restore(_ position: PDFPosition)
    var outline: [PDFOutlineItem] { get }
    var pageCount: Int { get }
    var currentPageIndex: Int? { get }
}

struct PDFOutlineItem: Identifiable, Sendable, Equatable {
    let id: UUID
    var title: String
    var pageIndex: Int?
    var children: [PDFOutlineItem]?      // nil for leaves (for OutlineGroup)
}

// ReaderModel additions (U7)
/// true only when `state == .ready`. The tab shows the colour menu, the inspector toggle and the inspector only then.
var isDocumentAvailable: Bool { get }
/// An engine couldn't show the document (PDFDocument(url:) returned nil; T55 uses it for an unreadable Markdown file).
/// Sets `state = .failed(message)` and `isRightPanelVisible = false`.
func engineFailed(_ message: String)
```
Behaviour:
- Defaults: `displayMode = .singlePageContinuous`, `displaysPageBreaks = true`, `autoScales = true` at first open, background `windowBackgroundColor`.
- Zoom in/out: `zoomIn(nil)`/`zoomOut(nil)` (turns `autoScales` off). Actual size: `autoScales = false; scaleFactor = 1`. Fit width: `scaleFactor` = (visible width − page margins) / current page crop-box width; `autoScales = false`.
- Single page toggles `.singlePage` ⇄ `.singlePageContinuous`.
- Position tracking: observe `NSView.boundsDidChangeNotification` of the scroll view's clip view (and `PDFViewPageChanged`); on change call `model.pdfPositionChanged(currentPosition, pageCount:)`. `PDFPosition.offsetY` = the page-space y of the top of the visible area on `pageIndex` (`currentDestination.point.y`). Restore with `go(to: PDFDestination(page:, at: CGPoint(x: 0, y: offsetY)))` after layout (dispatch to the next run loop turn).
- Engine actions registered: zoomIn, zoomOut, actualSize, fitWidth, toggleSinglePage, toggleThumbnails, currentPageIndex. Thumbnails: `PDFThumbnailView` bound to `pdfView` in a left column (width 140) toggled by the action.
- Chrome in `PDFReaderView`: bottom bar with a page field ("Page [n] of N"; Return jumps; invalid input resets), an outline button that shows an `OutlineGroup` popover when `outline` is non-empty (click → `go(toPage:)`).
- `.page(n)` locations: when `model.pendingLocation` is `.page`, call `go(toPage:)` then `model.consumeLocation()`. Other locations are handled by T59 (`.highlight`) and T67 (`.searchHit`).
- Never call `PDFDocument.write`. PDFKit objects stay on the main actor.
- Document > "Use Current Page as Cover" menu item is provided through the metadata sheet's "Use Current Page" (T50); nothing extra here.
- `PDFReaderController.load(url:)`: when `PDFDocument(url:)` returns nil, call `model.engineFailed(String(localized: "The document couldn't be opened."))` and register no engine actions.

Failed-load chrome (U7):
- `ReaderModel`: add `isDocumentAvailable` (`state == .ready`) and `engineFailed(_:)`. In `load()`, every path that sets `.failed` also sets `isRightPanelVisible = false` (a `.documentNote` location may have opened it). `toggleRightPanel(tab:)` returns without changing anything when `!isDocumentAvailable`.
- `ReaderTabContent.toolbarItems`: wrap the highlight-colour `ToolbarItem` and the "Highlights panel" `ToolbarItem` in `if model.isDocumentAvailable { … }` (the find and snapshot items already depend on engine actions, which a failed load never registers). The title and subtitle stay as they are (T52c).
- `ReaderTabContent`: bind the inspector to `Binding(get: { model.isDocumentAvailable && model.isRightPanelVisible }, set: { model.isRightPanelVisible = $0 })` instead of `Bindable(model).isRightPanelVisible`.
- `AppCommands`, View > Highlights Panel: `.disabled(readerActions?.model.isDocumentAvailable != true)`. Keep T52k's `.keyboardShortcut("i", modifiers: [.command, .option])` and the action.
- Edit Metadata… (⇧⌘M) stays available in a failed reader, as T52c left it.

## Tests (`PDFReaderControllerTests`, `@MainActor`)
Build a `ReaderModel` over an in-memory environment with a document whose file is `PDFFixtureBuilder.plainMultiPage(pageCount: 5)`; give `pdfView` a frame (600 × 800) inside an `NSWindow` (borderless, not shown) so layout runs.
- `loadsAndRegistersActions`: after `load(url:)`, `pageCount == 5`, `model.engineActions.zoomIn != nil`, `currentPageIndex == 0`.
- `restoresSavedPosition`: `restore(PDFPosition(pageIndex: 2, offsetY: 500))`, run the run loop briefly (`RunLoop.current.run(until: Date().addingTimeInterval(0.2))` — test code may use `Date()`), then `currentPosition()?.pageIndex == 2` and `abs(offsetY - 500) < 2`.
- `zoomCommands`: `actualSize()` → `scaleFactor == 1`, `autoScales == false`; `zoomIn()` → `scaleFactor > 1`; `fitWidth()` → `abs(scaleFactor - expected) < 0.01`.
- `outlineIsEmptyForFixture`: `outline.isEmpty` (fixtures have no outline).
- `damagedFileFailsTheModel`: `load(url:)` with a file containing `Data("not a pdf".utf8)` → `model.state == .failed("The document couldn't be opened.")`, `model.engineActions.zoomIn == nil`, `model.isDocumentAvailable == false`.

## Tests (`ReaderModelTests`, U7; use `ReaderTestSupport` as the existing tests do)
- `failedLoadHidesThePanelAndIgnoresToggle`: document inserted `withFile: false`; set `model.navigate(to: .documentNote)` before `await model.load()` (opens the panel); after load, `isDocumentAvailable == false` and `isRightPanelVisible == false`; `toggleRightPanel(tab: .highlights)` leaves `isRightPanelVisible == false`.
- `engineFailedMarksTheDocumentUnavailable`: document with a file; after `load()`, `isDocumentAvailable == true`; `toggleRightPanel(tab: .highlights)` → visible; `engineFailed("x")` → `state == .failed("x")`, `isDocumentAvailable == false`, `isRightPanelVisible == false`.

## UI test (`ReaderChromeTests`, U7)
- `testFailedReaderShowsNoColourMenuOrInspectorToggle`: launch, double-click `Sample.pendulum` (original missing); wait for the static text "The document file is missing." (5 s); assert `ui.highlightColorMenu.exists == false` and `ui.inspectorToggle.exists == false`; `ui.menuItemState("View", "Highlights Panel")` exists and is disabled; type ⌥⌘I and assert `ui.isInspectorOpen == false` after 1 s. Attach a screenshot "Failed reader chrome".

## Acceptance criteria
1. Position save/restore works through the controller. → test `PDFReaderControllerTests/restoresSavedPosition` (the model half is T51's `ReadingPositionTests/restoresPosition`)
2. Zoom, actual size and fit width set the expected scale. → test `PDFReaderControllerTests/zoomCommands`
3. Visual check (user), SPEC F-04 AC2: open a multi-page lecture PDF; scroll is continuous; View > Single Page switches to paged; ⌘+ / ⌘− zoom; ⌘0 actual size; ⌘9 fit width; thumbnails toggle and clicking a thumbnail jumps; the page field jumps to a typed page; for a PDF with a table of contents the outline popover lists it and jumps.
4. Visual check (user), SPEC F-04 AC1: scroll to the middle of page 7, close the document's tab, reopen the document from the library (and also after quitting the app) → it opens at the same place.
5. Visual check: resizing the window keeps the current page in view.
6. A failed reader (missing original, removed document, damaged PDF) shows no highlight-colour menu, no inspector toggle and no inspector, and View > Highlights Panel is disabled; a loaded reader keeps all three (U7). → tests `ReaderModelTests/failedLoadHidesThePanelAndIgnoresToggle`, `ReaderModelTests/engineFailedMarksTheDocumentUnavailable`, `PDFReaderControllerTests/damagedFileFailsTheModel`, UI test `ReaderChromeTests/testFailedReaderShowsNoColourMenuOrInspectorToggle`; these keep passing: `ReaderChromeTests/testMissingOriginalShowsErrorAndKeepsTheTitle`, `testInspectorToggleShowsHighlightsAndNotesTabs`, `testOptionCommandITogglesTheInspector`, `testHighlightColorMenuShowsColouredSwatchesAndKeepsTheChoice`, `testViewMenuReaderItemsAreDisabledNotMissing` (note: after T53 the zoom items are enabled for a loaded PDF; update that test deliberately to use `Sample.pendulum` (failed load, items still disabled) or to expect them enabled for `Sample.lecture`, and say which in the report).

The implementer doesn't run `./scripts/uitest.sh` (CLAUDE.md); ui-tester runs `./scripts/uitest.sh StudyReaderUITests/ReaderChromeTests` during review.

## Out of scope
- Dark-mode inversion (T54), highlights (T56, T59), snapshots (T61), find (T67).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-27, implementer pdf-engine Sonnet high (no reworks), reviewer code-reviewer Sonnet medium: APPROVED (conditional on the full unit run). PDF reader, position restore, zoom/fit/thumbnails/outline and U7 met; testViewMenuReaderItemsAreDisabledNotMissing now opens a failed-load document (spec-sanctioned) with a new enabled-case test. Backlog B5: skip tracking on restore timeout.
