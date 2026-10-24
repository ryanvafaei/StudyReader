# T63: Reader side panel: document highlights list and document notes

- **Phase:** 1 (E1.4/E1.5: F-06 highlights panel, F-08 thumbnails, F-09 document note)
- **Agent:** ui-builder
- **Depends on:** T62
- **ADRs:** docs/decisions/0017-reader-windows-and-commands.md, ARCHITECTURE §5.5 (order)
- **Visual check needed:** yes

## Goal
Fill the right column T52 created: a "Highlights" tab listing the document's highlights in reading order (color, rich text or thumbnail, note, tags, "PDF"/"Text" label for PDF documents, "Couldn't locate in document" for orphans; click scrolls to it) and a "Notes" tab with the document note editor (autosave, F-09).

## Files to touch
- `StudyReader/Features/Reader/Chrome/HighlightsPanelModel.swift` (new)
- `StudyReader/Features/Reader/Chrome/HighlightsPanelView.swift` (new)
- `StudyReader/Features/Reader/Chrome/DocumentNotePanelView.swift` (new)
- `StudyReader/Features/Reader/ReaderWindowView.swift` (modify: replace the panel placeholder)
- `StudyReaderTests/ReaderTests/HighlightsPanelModelTests.swift` (new)

## Interfaces to produce
```swift
struct PanelHighlightRow: Identifiable, Equatable {
    let highlight: Highlight
    let tagNames: [String]
    var id: String { highlight.id }
    var viewLabel: String?          // "PDF" for view .pdf, "Text" for .text/.markdown, nil when the document is Markdown
    var isOrphaned: Bool { highlight.anchorStatus == .orphaned }
}
struct PanelSection: Identifiable, Equatable {
    let title: String?              // "PDF view" / "Text view" for PDF documents with both kinds; nil otherwise
    let rows: [PanelHighlightRow]
    var id: String { title ?? "all" }
}

@MainActor @Observable
final class HighlightsPanelModel {
    init(model: ReaderModel)
    private(set) var sections: [PanelSection] = []
    /// Rebuilds sections from model.highlights plus tag names (tagRepository.tags(forHighlight:) per highlight;
    /// don't add repository methods in this task).
    func refresh() async
    func select(_ highlightId: String)          // model.navigate(to: .highlight(id))
    nonisolated static func sections(for highlights: [Highlight], tagNames: [String: [String]], fileType: FileType) -> [PanelSection]
}
```
- Order: within a section, `positionKey` then `createdAt` (ARCHITECTURE §5.5). For PDF documents, PDF-view highlights (view `.pdf`, including image highlights) form one section and text-view ones (`.text`) another; if only one kind exists there's a single untitled section. Markdown documents: one untitled section.
- Row: color bar, `RichTextView(highlight.editedText.map(RichTextMarkdown.escape) ?? highlight.richText)` (3 lines) or the image thumbnail (height 60), note excerpt (2 lines, secondary), tags as `#name`, page "p. N" (pageIndex + 1) when present, `viewLabel` badge, orphan notice "Couldn't locate in document" (italic, secondary). Click → `select`. Context menu: "Show in Document" (`select`) and "Delete" (`highlightService.delete`).
- `refresh()` runs on `.task` and `.onChange(of: model.highlights)`.
- Notes tab: `DocumentNotePanelView` with `NoteEditorModel(target: .document(documentId))`: `TextEditor` filling the column, placeholder "Notes for this document…", and below it a rendered preview toggle ("Preview") that shows the note with `AttributedString(markdown:)` full syntax (lists and line breaks, F-09). `flush()` on disappear and on tab switch.
- Empty states: "No highlights yet. Select text to highlight it." / "No notes yet."

## Tests (`HighlightsPanelModelTests`)
- `sectionsForPDFDocument`: highlights with views `.pdf` (keys 2_000_100, 100), `.text` (key 5) → two sections titled "PDF view" (sorted by key) and "Text view"; labels "PDF"/"Text".
- `singleSectionForMarkdown`: `.markdown` highlights → one untitled section, `viewLabel == nil`.
- `orphansAreListed`: an orphaned highlight appears with `isOrphaned`.
- `tagsAttached`: `tagNames` map is applied per row.

## Acceptance criteria
1. Panel order, sections, labels and orphan rows follow the spec. → tests `HighlightsPanelModelTests/*`
2. Visual check (user): ⌥⌘H opens the panel; highlights are listed in reading order with color, text (or snapshot thumbnail), note, tags and page; clicking one scrolls the PDF/Markdown view to it; deleting from the context menu removes it from the page.
3. Visual check, SPEC F-09 AC1: the Notes tab edits the document note; stop typing, wait one second, quit, relaunch → the note is kept; Preview renders lists.
4. Visual check, SPEC F-08 AC2 (part): image highlights show thumbnails in the panel.

## Out of scope
- Search hits in notes (T65/T66), export (T70).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
