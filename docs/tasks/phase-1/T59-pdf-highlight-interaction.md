# T59: PDF highlight interaction: create, draw, click, keys, undo

- **Phase:** 1 (E1.4: F-06 in PDF view)
- **Agent:** pdf-engine
- **Depends on:** T51, T56, T58
- **ADRs:** docs/decisions/0004-highlight-anchoring.md, docs/decisions/0017-reader-windows-and-commands.md, ARCHITECTURE §5.1
- **Reference:** `.references/YoPDF/macos/YoPDFCore/MarkupAnnotation.swift`, `MarkupEditing.swift` (recolor/delete, undo patterns); `.references/reader-source/Reader/Formats/PDF/PDFKitReadingAdapter.swift` (display-only annotations, mouse handling). Auto-highlight behaviour: Marvelxy/PDFReader README only (GPL: never open its code).
- **Visual check needed:** yes

## Goal
Make highlighting work in the PDF view (SPEC F-06): releasing the mouse after a selection creates a highlight in the current color (auto-highlight on) or asks the selection toolbar (off); 1–5 / H highlight the selection; ⌘Z right after an auto-highlight removes it; stored highlights are drawn as display-only annotations and stay in place after zoom, resize and restart; clicking a highlight opens its popover (topmost wins); `.highlight(id)` locations scroll to it.

## Files to touch
- `StudyReader/Features/Reader/PDF/PDFHighlightController.swift` (new: sync annotations with `model.highlights`, hit testing, selection → `NewTextHighlight`)
- `StudyReader/Features/Reader/PDF/StudyPDFView.swift` (modify: mouse/key hooks, undo registration)
- `StudyReader/Features/Reader/PDF/PDFReaderController.swift` (modify: own the highlight controller, handle `.highlight` locations)
- `StudyReader/Features/Reader/PDF/PDFReaderView.swift` (modify: observe `model.highlights` changes)
- `StudyReaderTests/ReaderTests/PDFHighlightControllerTests.swift` (new)

## Interfaces to produce
```swift
@MainActor
final class PDFHighlightController {
    init(model: ReaderModel, pdfView: StudyPDFView)
    /// Diff by highlight id + color: remove annotations of deleted/recolored highlights, add new ones
    /// (only kind .text with anchor .pdf and anchorStatus .ok). Adds in createdAt order so newer ones draw on top.
    func sync(with highlights: [Highlight])
    /// Highlight ids under a page-space point on pageIndex, newest (createdAt) first.
    func highlightIds(at point: CGPoint, onPage pageIndex: Int) -> [String]
    /// NewTextHighlight for the selection: PDFAnchorBuilder anchor, view .pdf, richText = RichTextMarkdown.escape(text),
    /// pageIndex = firstPageIndex, color = given color. nil for empty selections.
    func newHighlight(for selection: PDFSelection, color: HighlightColor) -> NewTextHighlight?
    /// Scrolls so the highlight's first rect is visible (go(to: rect, on: page)) and flashes it briefly.
    func reveal(highlightId: String)
    private(set) var annotationCount: Int     // for tests
}
```
Behaviour:
- `onSelectionFinished` (mouseUp with a non-empty selection): `newHighlight(for:color: settings.currentColor)` → `await model.selectionFinished(new, anchorRect:)`, where `anchorRect` is the selection's last-line bounds converted to the representable's top-left coordinates. After an auto-highlight is created, clear the PDF selection and register undo: `pdfView.undoManager?.registerUndo(withTarget: self) { _ in Task { await model.undoLastAutoHighlight() } }` with action name "Highlight".
- `onKeyDown` with a non-empty selection: keys "1"–"5" → color rawValue 0–4, "h"/"H" → current color → `model.createHighlight(new, isAuto: false)`; consumed. Without a selection, not consumed.
- `onClick` (no drag): convert to page space; `highlightIds(at:onPage:)`; the first id → `model.showPopover(highlightId:anchorRect:)` (rect = that annotation's bounds in view coordinates, top-left origin); return true. No hit → false (normal PDFView behaviour).
- `sync` runs whenever `model.highlights` changes (SwiftUI `.onChange(of: model.highlights)` in `PDFReaderView`, calling into the controller). Annotations are added with `page.addAnnotation`, removed with `page.removeAnnotation`; never `document.write`.
- Pending `.highlight(id)` location: `reveal(highlightId:)`, then `model.consumeLocation()`. Orphaned or image highlights: reveal the page (`go(toPage: pageIndex)`) only.
- Labels "PDF"/"Text" in the panel come from `view` (T63); nothing here.

## Tests (`PDFHighlightControllerTests`, `@MainActor`)
In-memory environment, a document with `plainMultiPage(pageCount: 3)` as its file, `ReaderModel` loaded, a `StudyPDFView` (600 × 800) in a borderless window with the document.
- `syncAddsAndRemovesAnnotations`: two highlights (anchors built with `PDFAnchorBuilder` from real selections, one spanning pages 0–1) → `annotationCount == 3`; recolor one → still 3 and its annotations have the new color; delete one → count drops accordingly.
- `newerHighlightWinsHitTest`: two overlapping highlights (created 1 s apart) → `highlightIds(at:)` at a point inside both returns the newer first.
- `newHighlightUsesEscapedText`: a selection over "line 1: The quick" → `richText == RichTextMarkdown.escape(text)`, `view == .pdf`, `pageIndex == 0`, `positionKey == anchor.positionKey`.
- `orphanedAndImageHighlightsNotDrawn`: an `.orphaned` text highlight and an image highlight add no `StudyHighlightAnnotation`.
- `annotationsMatchStoredRects`: after `sync`, each annotation's bounds equals `PDFHighlightGeometry.bounds(of:)` of its stored rects, independent of `scaleFactor` (set 0.5 then 2.0 and compare again).

## Acceptance criteria
1. Annotations follow the stored highlights and stay at their page-space rects at any zoom. → tests `syncAddsAndRemovesAnnotations`, `annotationsMatchStoredRects`
2. Topmost (newest) highlight wins clicks. → test `newerHighlightWinsHitTest`
3. Visual check (user), SPEC F-06 AC1: with auto-highlight on, select a sentence → it turns the current color at once; ⌘Z right after removes it. With auto-highlight off (Settings), selecting shows the selection toolbar (after T62; before T62 nothing happens and no highlight is created).
4. Visual check, SPEC F-06 AC2/AC3: a selection across two lines and one across a page break each become one highlight; zoom in/out, resize the window, quit and relaunch → highlights sit exactly on the same text (send screenshots before/after).
5. Visual check: select text and press 3 → blue highlight; H → current color; click an existing highlight → popover opens (after T62; before T62, `model.popoverRequest` is set and nothing visible happens); overlapping highlights: the newest one is drawn on top and is the one clicked.

## Out of scope
- Popover and selection toolbar UI (T62), panel (T63), snapshots (T61), PDF rich text from attributes (Phase 3).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
