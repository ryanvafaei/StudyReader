# T61: Snapshot service and snapshot tool (image highlights)

- **Phase:** 1 (E1.4: F-08; F-04 AC3 "snapshots stay uninverted")
- **Agent:** pdf-engine
- **Depends on:** T59
- **ADRs:** ARCHITECTURE §3, §5.4, §5.5
- **Visual check needed:** yes

## Goal
Snapshot tool (SPEC F-08): toolbar camera button or ⌃⌘S (PDF view only) turns the cursor into a crosshair; dragging a rectangle on a page saves a PNG of that region rendered from the page at 2×, uninverted, as an image highlight with color, note and tags. Rectangles are clipped to the page; under 10 × 10 pt they're ignored. Image highlights get a thin outline in the PDF view so they can be clicked.

## Files to touch
- `StudyReader/Features/Reader/PDF/SnapshotService.swift` (new)
- `StudyReader/Features/Reader/PDF/SnapshotTool.swift` (new: drag overlay/mode inside `StudyPDFView`)
- `StudyReader/Features/Reader/PDF/StudyPDFView.swift`, `PDFReaderController.swift`, `PDFHighlightController.swift` (modify)
- `StudyReaderTests/ReaderTests/SnapshotServiceTests.swift` (new)

## Interfaces to produce
```swift
enum SnapshotService {
    static let scale: CGFloat = 2
    static let minimumSide: CGFloat = 10
    /// rect ∩ pageBounds (crop box); nil if the result is narrower or shorter than minimumSide.
    static func clippedRect(_ rect: CGRect, pageBounds: CGRect) -> CGRect?
    /// Opens its own PDFDocument(url:) (call off the main actor). Renders page `pageIndex` cropped to `rect`
    /// (page space) at `scale` on opaque white into a CGContext via PDFPage.draw(with: .cropBox, to:),
    /// returns PNG data. Never uses the screen or the view, so it's always uninverted.
    static func renderPNG(fileAt url: URL, pageIndex: Int, rect: CGRect) throws -> Data
}
enum SnapshotError: Error, Equatable { case cannotOpen, pageOutOfRange, emptyRect, encodeFailed }
```
Tool and creation:
- `ReaderEngineActions.startSnapshot` toggles snapshot mode; Escape cancels; crosshair cursor (`NSCursor.crosshair`) while active; a translucent selection rectangle follows the drag.
- On mouseUp: convert the drag rect to page space on the page under the start point (`convert(_:to: page)`); `clippedRect`; nil → leave mode silently. Else `Task.detached { try SnapshotService.renderPNG(fileAt:pageIndex:rect:) }`, then `environment.highlightService.createImage(NewImageHighlight(documentId:, pageIndex:, rect: CGRectCodable(clipped), positionKey: PDFAnchorBuilder.positionKey(pageIndex:, pageHeight:, topOfFirstRect: clipped.maxY), color: settings.currentColor, pngData:))`. Errors → `model.transientMessage`. Exit snapshot mode after one capture.
- Drawing: `PDFHighlightController.sync` adds, for each image highlight, a display-only `PDFAnnotation` of subtype `.square` with the highlight color border (1.5 pt, alpha 0.8, no fill), and includes it in hit testing (clicking it opens the popover).
- Snapshot mode is only available in PDF documents (the action is registered by the PDF controller only).

## Tests (`SnapshotServiceTests`)
- `rendersRegion` (SPEC F-08 AC1): `coloredRegion()` fixture; `renderPNG(rect: PDFFixtureBuilder.coloredRect)` → PNG of exactly 400 × 300 px; the center pixel is red (R > 200, G < 60, B < 60); all four corner pixels (inset 3 px) are red too (the rect is fully red).
- `capturesUninverted` (SPEC F-04 AC3): render a rect that covers part red and part white (`coloredRect.insetBy(dx: -20, dy: -20)`) inside `NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance { … }` and also with `NSApp.appearance = .darkAqua` set during the call (restore afterwards); the red region is red and the margin is white (R, G, B > 240).
- `clipsToPage`: `clippedRect(CGRect(x: -50, y: -50, width: 100, height: 100), pageBounds: (0, 0, 612, 792))` == (0, 0, 50, 50); a rect fully outside → nil.
- `ignoresTinyRects`: 9 × 50 → nil; 10 × 10 → non-nil.
- `errors`: page 5 of a 1-page PDF → `.pageOutOfRange`; damaged PDF → `.cannotOpen`.

## Acceptance criteria
1. A rectangle saves a PNG of exactly that region at 2×. → test `SnapshotServiceTests/rendersRegion`
2. Snapshots are uninverted regardless of appearance. → test `SnapshotServiceTests/capturesUninverted`
3. Clipping and the minimum size rule apply. → tests `clipsToPage`, `ignoresTinyRects`, `errors`
4. Visual check (user): click the camera button (or ⌃⌘S) in a PDF; the cursor is a crosshair; drag over a figure → an outlined image highlight appears; in dark mode with inversion on, the snapshot (seen in the panel after T63, or by opening `Documents/<id>/snapshots/` in Finder via Settings > Data) has the original light colors (T54 check 3).
5. Visual check, SPEC F-08 AC2: image highlights show their thumbnail in the document panel (T63) and the highlights browser (T69); confirmed at those tasks' checks.

## Out of scope
- Showing image highlights in review (Phase 2), notes/tags UI (T62).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
