# T53: PDF reader view: display, navigation, reading position

- **Phase:** 1 (E1.2: F-04)
- **Agent:** pdf-engine
- **Depends on:** T52
- **ADRs:** docs/decisions/0017-reader-windows-and-commands.md, docs/decisions/0003-grdb-fts5-database-of-record.md (never write PDFs), ARCHITECTURE §3, §5.1
- **Reference:** `.references/YoPDF/macos/YoPDF/Reader/PDFViewerRepresentable.swift` (NSViewRepresentable wrapper, selection and mouse handling); `.references/reader-source/Reader/Formats/PDF/PDFKitReadingAdapter.swift` (PDFView subclass patterns). Read only these.
- **Visual check needed:** yes

## Goal
Replace T52's PDF placeholder with a PDFKit reader: continuous (default) or single-page display, zoom in/out, actual size, fit width, page thumbnails sidebar, page number field, outline, and reading position saved and restored through `ReaderModel` (F-04). Highlights and snapshots come in T56–T61; this task leaves clean extension points for them.

## Files to touch
- `StudyReader/Features/Reader/PDF/StudyPDFView.swift` (new: `PDFView` subclass)
- `StudyReader/Features/Reader/PDF/PDFReaderController.swift` (new: owns the view, registers engine actions)
- `StudyReader/Features/Reader/PDF/PDFReaderView.swift` (new: `NSViewRepresentable` + SwiftUI chrome: page field, outline popover, thumbnails)
- `StudyReader/Features/Reader/PDF/PDFOutlineItem.swift` (new)
- `StudyReader/Features/Reader/ReaderWindowView.swift` (modify: the PDF branch of `ReaderContentSlot`)
- `StudyReaderTests/ReaderTests/PDFReaderControllerTests.swift` (new)

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

## Tests (`PDFReaderControllerTests`, `@MainActor`)
Build a `ReaderModel` over an in-memory environment with a document whose file is `PDFFixtureBuilder.plainMultiPage(pageCount: 5)`; give `pdfView` a frame (600 × 800) inside an `NSWindow` (borderless, not shown) so layout runs.
- `loadsAndRegistersActions`: after `load(url:)`, `pageCount == 5`, `model.engineActions.zoomIn != nil`, `currentPageIndex == 0`.
- `restoresSavedPosition`: `restore(PDFPosition(pageIndex: 2, offsetY: 500))`, run the run loop briefly (`RunLoop.current.run(until: Date().addingTimeInterval(0.2))` — test code may use `Date()`), then `currentPosition()?.pageIndex == 2` and `abs(offsetY - 500) < 2`.
- `zoomCommands`: `actualSize()` → `scaleFactor == 1`, `autoScales == false`; `zoomIn()` → `scaleFactor > 1`; `fitWidth()` → `abs(scaleFactor - expected) < 0.01`.
- `outlineIsEmptyForFixture`: `outline.isEmpty` (fixtures have no outline).

## Acceptance criteria
1. Position save/restore works through the controller. → test `PDFReaderControllerTests/restoresSavedPosition` (the model half is T51's `ReadingPositionTests/restoresPosition`)
2. Zoom, actual size and fit width set the expected scale. → test `PDFReaderControllerTests/zoomCommands`
3. Visual check (user), SPEC F-04 AC2: open a multi-page lecture PDF; scroll is continuous; View > Single Page switches to paged; ⌘+ / ⌘− zoom; ⌘0 actual size; ⌘9 fit width; thumbnails toggle and clicking a thumbnail jumps; the page field jumps to a typed page; for a PDF with a table of contents the outline popover lists it and jumps.
4. Visual check (user), SPEC F-04 AC1: scroll to the middle of page 7, close the window, reopen the document (and also after quitting the app) → it opens at the same place.
5. Visual check: resizing the window keeps the current page in view.

## Out of scope
- Dark-mode inversion (T54), highlights (T56, T59), snapshots (T61), find (T67).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
