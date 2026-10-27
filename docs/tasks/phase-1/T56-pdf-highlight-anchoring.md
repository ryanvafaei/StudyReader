# T56: PDF highlight anchoring and display annotations

- **Phase:** 1 (E1.4: F-06 PDF view geometry)
- **Agent:** pdf-engine
- **Depends on:** T53
- **ADRs:** docs/decisions/0004-highlight-anchoring.md, ARCHITECTURE §5.1, §5.5 (read both in full)
- **Reference:** `.references/YoPDF/macos/YoPDFCore/HighlightService.swift` (per-line rects, one annotation per page, quads relative to bounds). Read only this file. Copying > 20 lines needs the Apache-2.0 notice and a `THIRD_PARTY_NOTICES.md` entry.
- **Visual check needed:** no (T59 shows highlights on screen)

## Goal
Pure geometry for PDF-view highlights: turn a `PDFSelection` into a `PDFAnchor` (per-line rects in page space for each touched page, text, prefix/suffix), compute `positionKey`, and build display-only `StudyHighlightAnnotation`s whose quads are relative to their bounds, so highlights redraw in exactly the same place after zoom, resize and restart.

## Files to touch
- `StudyReader/Features/Reader/PDF/PDFAnchorBuilder.swift` (new)
- `StudyReader/Features/Reader/PDF/StudyHighlightAnnotation.swift` (new)
- `StudyReaderTests/ReaderTests/PDFAnchorTests.swift` (new)

## Interfaces to produce
```swift
struct PDFSelectionAnchor: Sendable, Equatable {
    var anchor: PDFAnchor          // Core/Models/Anchor.swift
    var firstPageIndex: Int
    var positionKey: Double
    var text: String               // selection.string, line breaks kept
}

@MainActor
enum PDFAnchorBuilder {
    static let contextLength = 32
    /// nil when the selection has no non-whitespace text. For each page in selection.pages (document order):
    /// rects = selection.selectionsByLine() filtered to that page → bounds(for: page), each rect with
    /// width and height > 0.5, in line order. prefix/suffix = up to 32 characters of the page text
    /// (page.string) immediately before/after the selection on its first/last page (empty at page edges).
    static func anchor(for selection: PDFSelection, in document: PDFDocument) -> PDFSelectionAnchor?
    /// ARCHITECTURE §5.5: Double(pageIndex) * 1_000_000 + (pageHeight - topOfFirstRect), pageHeight = crop box height.
    static func positionKey(pageIndex: Int, pageHeight: Double, topOfFirstRect: Double) -> Double
}

enum PDFHighlightGeometry {
    /// Union of the rects.
    static func bounds(of rects: [CGRect]) -> CGRect
    /// 4 points per rect, relative to bounds.origin, in PDFKit quad order:
    /// (minX, maxY), (maxX, maxY), (minX, minY), (maxX, minY).
    static func quadrilateralPoints(for rects: [CGRect], relativeTo origin: CGPoint) -> [CGPoint]
}

/// Display-only (never saved into the file). One per page entry of a highlight.
@MainActor
final class StudyHighlightAnnotation: PDFAnnotation {
    let highlightId: String
    let createdAt: Date
    init(highlightId: String, createdAt: Date, pageRects: [CGRect], color: NSColor)
    // subtype .highlight, bounds = PDFHighlightGeometry.bounds, quadrilateralPoints as NSValue(point:),
    // color = the passed NSColor as is (callers pass HighlightPalette.nsColor(c).withAlphaComponent(0.35)), shouldPrint false
}

extension StudyHighlightAnnotation {
    /// One annotation per PDFAnchor.PageRects entry, for the given highlight.
    static func annotations(for highlight: Highlight, color: NSColor) -> [(pageIndex: Int, annotation: StudyHighlightAnnotation)]
}
```
- Selection text for anchors: `selection.string ?? ""`. Character offsets for prefix/suffix: use the first line selection's `range(at: 0, on: page)` (`PDFSelection.range(at:on:)`) on the first page and the last range on the last page.
- Image highlights (`.image` anchors) get a separate square annotation in T61; not here.

## Tests (`PDFAnchorTests`, `@MainActor`)
Fixture: `PDFFixtureBuilder.plainMultiPage(pageCount: 5)` loaded with `PDFDocument(data:)`. Build selections with `document.selection(from:atCharacterIndex:to:atCharacterIndex:)` using character indexes found in `page.string`.
- `multiLineAndCrossPage` (SPEC F-06 AC2): a selection from the start of "line 9" on page 0 to the end of "line 2" on page 1 → `anchor.pages.map(\.pageIndex) == [0, 1]`, page 0 has 2 rects (lines 9 and 10), page 1 has 2 rects; every rect lies inside its page's crop box; `text` contains "line 10"; `firstPageIndex == 0`.
- `singleLine`: a selection inside one line → one page entry, one rect; prefix ends with the characters just before the selection; suffix starts with those just after.
- `roundTrip` (SPEC F-06 AC3): anchor → `JSONEncoder` → `JSONDecoder` → equal `PDFAnchor`; annotations built from the decoded anchor have `bounds == bounds(of: rects)` for each page and `quadrilateralPoints` equal to `quadrilateralPoints(for: rects, relativeTo: bounds.origin)`; the quads, offset by `bounds.origin`, reproduce the original rects' corners exactly. Building the annotations twice gives identical bounds and quads (zoom and resize don't enter the computation).
- `positionKeyOrders`: keys for (page 0, top 700), (page 0, top 300), (page 1, top 700) are strictly increasing in that order.
- `whitespaceSelectionIsNil`: a selection covering only spaces → nil.

## Acceptance criteria
1. Multi-line and cross-page selections produce one anchor with the right rects per page. → test `PDFAnchorTests/multiLineAndCrossPage`
2. Anchors and annotations round-trip exactly; quads are relative to bounds. → test `PDFAnchorTests/roundTrip`
3. Reading order and empty selections behave as specified. → tests `positionKeyOrders`, `singleLine`, `whitespaceSelectionIsNil`

## Out of scope
- Mouse/keyboard handling, drawing in the view, popover (T59, T62).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-27, implementer pdf-engine Sonnet high (no reworks), reviewer code-reviewer Sonnet medium: APPROVED (conditional on the full unit run). Anchors from selectionsByLine in page space, 0.5 pt filter, display-only annotation never written to the PDF; PDFAnchorTests 6/6 on CI. Backlog B9: no test for rotated pages or a non-zero crop box origin.
