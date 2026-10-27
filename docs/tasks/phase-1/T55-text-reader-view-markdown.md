# T55: TextReaderView and the Markdown reader

- **Phase:** 1 (E1.3: F-03 rendering on screen)
- **Agent:** pdf-engine
- **Depends on:** T43, T52, T53 (`ReaderModel.engineFailed(_:)`)
- **ADRs:** docs/decisions/0005-text-rendering-nstextview.md, docs/decisions/0017-reader-windows-and-commands.md, ARCHITECTURE §5.2, §7
- **Visual check needed:** yes

## Goal
Replace T52's Markdown placeholder with a read-only, selectable TextKit 2 text view showing `MarkdownRenderer` output: code block backgrounds, block quote bars, horizontal rules, image attachments and placeholders, clickable links, a centered 720 pt content column, and reading position (first visible character) saved and restored. The same `TextReaderView` will show the PDF text view in Phase 3, so keep Markdown-specific code out of it.

## Files to touch
- `StudyReader/Features/Reader/Text/TextReaderView.swift` (new: `NSTextView` subclass + scroll view setup)
- `StudyReader/Features/Reader/Text/TextReaderController.swift` (new)
- `StudyReader/Features/Reader/Text/TextBlockDecorations.swift` (new: TextKit 2 layout fragment drawing for the custom attributes)
- `StudyReader/Features/Reader/Markdown/MarkdownReaderView.swift` (new: `NSViewRepresentable`, loads and renders the file)
- `StudyReader/Features/Reader/ReaderWindowView.swift` (modify: the Markdown branch of `ReaderContentSlot`)
- `StudyReaderTests/ReaderTests/TextReaderControllerTests.swift` (new)

## Interfaces to produce
```swift
@MainActor
final class TextReaderView: NSTextView {
    /// Created with NSTextView(usingTextLayoutManager: true) semantics; isEditable false, isSelectable true,
    /// usesFindBar true, isIncrementalSearchingEnabled true, drawsBackground true.
    var onSelectionFinished: (@MainActor (NSRange) -> Void)?   // after mouseUp with a non-empty selection (T60)
    var onClick: (@MainActor (Int, NSEvent) -> Bool)?          // character index at click; true if handled (T60)
    var onKeyDown: (@MainActor (NSEvent) -> Bool)?             // 1–5 / H (T60)
}

@MainActor
final class TextReaderController {
    let scrollView: NSScrollView
    let textView: TextReaderView
    static let contentWidth: CGFloat = 720          // F-05 "Medium"; appearance settings come in Phase 3
    init(model: ReaderModel)
    /// Sets the attributed string, restores model.initialTextOffset, registers engine actions
    /// (findInDocument → NSTextFinder action .showFindInterface, copySelection), starts position tracking.
    func load(_ attributedString: NSAttributedString)
    /// UTF-16 offset of the first character whose line fragment is visible at the top.
    func firstVisibleOffset() -> Int
    func scroll(toOffset offset: Int)               // top of that line at the top of the visible area
    func select(_ range: NSRange)                    // set selection + scrollRangeToVisible
    /// Rect of `range` in the representable's coordinate space, top-left origin (for popover anchors).
    func anchorRect(for range: NSRange) -> CGRect
    var textLength: Int { get }
}
```
Behaviour:
- `MarkdownReaderView(model:)`: on load, read the stored file as UTF-8 (failure → `model.engineFailed(String(localized: "Couldn't read this document."))`, added by T53; the shared chrome then hides the colour menu and inspector toggle, U7), `MarkdownRenderer.render(MarkdownDocumentSource(markdown:, documentId:, fileStore:))`, keep the `RenderedMarkdown` in the coordinator (T58/T60 need `sourceMap`), call `controller.load(rendered.attributedString)`.
- Content column: `textContainerInset` width = max(24, (scroll view width − 720) / 2), recomputed on resize; vertical inset 32.
- Decorations: `NSTextLayoutManagerDelegate.textLayoutManager(_:textLayoutFragmentFor:in:)` returns a fragment subclass for paragraphs carrying `.studyCodeBlock` (rounded background, `quaternarySystemFill`), `.studyBlockQuote` (3 pt left bar, `separatorColor`) or `.studyHorizontalRule` (1 pt line across the column). Plain paragraphs use the default fragment.
- Links: only `http`, `https`, `mailto` open (`NSWorkspace.shared.open`); others are ignored. Override `clicked(onLink:at:)` (or the delegate method) accordingly.
- Position: observe the clip view's bounds changes; call `model.textPositionChanged(offset: firstVisibleOffset(), textLength:)`. Restore after the first layout (next run loop turn).
- No editing: paste, drag-edit and spelling are off. Copy works.

## Tests (`TextReaderControllerTests`, `@MainActor`)
Model over an in-memory environment with a Markdown document (file = `all-elements.md` copied into its folder); controller views in a borderless `NSWindow` 900 × 700.
- `loadsRenderedText`: `textLength == rendered.string.utf16.count`; `textView.isEditable == false`; `textView.textLayoutManager != nil` (TextKit 2).
- `scrollRoundTrip`: `scroll(toOffset: <offset of "Final paragraph">)`, run the run loop 0.2 s; `abs(firstVisibleOffset() - target) <= <length of that line>`.
- `restoresInitialOffset`: a document whose `textPosition` is set before load → after load and a run-loop turn, `firstVisibleOffset()` is within one line of it.
- `anchorRectIsInsideView`: `anchorRect(for:)` of a visible range has positive size and lies within the view bounds.
- `insetCentersColumn`: with a 1200 pt wide scroll view, the horizontal inset is 240.

## Acceptance criteria
1. Rendering, scrolling and position restore work in the controller. → tests `TextReaderControllerTests/*`
2. Visual check (user), SPEC F-03 AC1: import `StudyReaderTests/Fixtures/markdown/all-elements.md` (the whole `markdown` folder plus an `images/diagram.png` from `MarkdownFixtures.makeFolderWithImages()`'s layout, or any folder with that structure) and open it: H1–H6 are visibly different sizes; emphasis, strong, inline code, strikethrough, block quote (left bar), lists with bullets/numbers/checkboxes, the table as aligned columns, the code block on a gray background, the horizontal rule, the local image, and placeholders for the missing and remote images (the remote one showing its URL) are all distinct; the link opens Safari.
3. Visual check: text is selectable and copyable but not editable; the column is centered at about 720 pt; reopening the document returns to the same scroll position.

## Out of scope
- Highlights in the text view (T60), find bar wiring beyond the engine action (T67), appearance settings and paged layout (Phase 3).
- The failed-load chrome (U7): T53 already did it in the shared `ReaderTabContent`; don't change the toolbar or inspector binding here, only call `engineFailed(_:)` on a read failure.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
