# T60: Markdown highlight interaction: create, draw, re-anchor, click, keys, undo

- **Phase:** 1 (E1.4: F-06 in the Markdown view, F-07 for Markdown)
- **Agent:** pdf-engine
- **Depends on:** T51, T55, T57, T58
- **ADRs:** docs/decisions/0004-highlight-anchoring.md, docs/decisions/0005-text-rendering-nstextview.md, ARCHITECTURE §5.2–§5.3
- **Visual check needed:** yes

## Goal
Make highlighting work in the Markdown view: selection → highlight (auto or toolbar), 1–5 / H, ⌘Z undo, drawing with TextKit 2 rendering attributes (offsets stay stable), click → popover (topmost wins), re-anchoring on open when the renderer version or text changed (orphans stay listed but aren't drawn), and `.highlight(id)` navigation.

> Note: T63a replaced the TextKit 2 rendering attributes described below with painting in `TextReaderView.drawBackground(in:)` from `highlightPaints` (see the ADR-0005 amendment); the rendering-attribute wording in this spec is historical.

## Files to touch
- `StudyReader/Features/Reader/Text/TextHighlightController.swift` (new)
- `StudyReader/Features/Reader/Text/TextReaderView.swift`, `TextReaderController.swift` (modify: hooks, undo)
- `StudyReader/Features/Reader/Markdown/MarkdownReaderView.swift` (modify: wire the controller, re-anchor after load)
- `StudyReaderTests/ReaderTests/TextHighlightControllerTests.swift` (new)

## Interfaces to produce
```swift
@MainActor
final class TextHighlightController {
    init(model: ReaderModel, textController: TextReaderController)
    /// Rendered string + source map of the current document (set after load).
    func setRendered(string: String, sourceMap: MarkdownSourceMap)
    /// Removes all highlight rendering attributes, then adds .backgroundColor
    /// (HighlightPalette.nsColor(color).withAlphaComponent(0.35)) for each ok text highlight with a .text anchor,
    /// in createdAt order (newest drawn last). Uses NSTextLayoutManager.addRenderingAttribute(_:value:for:)
    /// with NSTextRange built from the anchor's NSRange.
    func sync(with highlights: [Highlight])
    /// Ids of highlights containing the UTF-16 index, newest first.
    func highlightIds(atCharacterIndex index: Int) -> [String]
    /// NewTextHighlight for a range: TextAnchoring.anchor(sourceVersion: MarkdownRenderer.version), view .markdown,
    /// richText = RichTextMarkdown.markdown(for:in:sourceMap:), text = plain substring, pageIndex nil,
    /// positionKey = TextAnchoring.positionKey(for:). nil for whitespace-only ranges.
    func newHighlight(for range: NSRange, color: HighlightColor) -> NewTextHighlight?
    /// For every .text highlight: TextAnchoring.resolve(anchor, in: string, currentVersion: MarkdownRenderer.version).
    /// .moved → highlightRepository.updateAnchor(anchor: .text(new), positionKey:, status: .ok);
    /// .orphaned (and status was .ok) → updateAnchor(same anchor, same positionKey, status: .orphaned);
    /// an orphaned highlight that resolves again → status .ok. Returns the number of rows changed.
    func reanchorAll(_ highlights: [Highlight]) async -> Int
    func reveal(highlightId: String)          // controller.select(range) + scroll; orphaned → no-op
}
```
Behaviour:
- After the document renders (T55), call `reanchorAll(model.highlights)` once per open (after the first highlights arrive), then `sync`. Re-anchoring writes go through `HighlightRepository.updateAnchor` (column-limited, no FTS churn).
- `onSelectionFinished(range)`: `newHighlight(for:color: currentColor)` → `model.selectionFinished(new, anchorRect: textController.anchorRect(for: range))`; after an auto-highlight, collapse the selection and register undo on `textView.undoManager` calling `model.undoLastAutoHighlight()` (action name "Highlight").
- `onKeyDown` with a selection: "1"–"5", "h"/"H" → `model.createHighlight(..., isAuto: false)`.
- `onClick(index)`: first id from `highlightIds(atCharacterIndex:)` → `model.showPopover(highlightId:anchorRect:)` with the highlight's range rect; true. Otherwise false.
- `sync` on every `model.highlights` change.
- Pending `.highlight(id)` location → `reveal`, then `consumeLocation()`.

## Tests (`TextHighlightControllerTests`, `@MainActor`)
In-memory environment; a Markdown document whose file is `rich-inline.md` (and one with `all-elements.md`); controllers in a borderless window.
- `newHighlightStoresRichText`: range of the whole line → `richText == "a **bold** and *italic* word with `code`"`, `view == .markdown`, anchor `.text` with `sourceVersion == MarkdownRenderer.version`, `positionKey == 0`.
- `reanchorMovesAndOrphans`: store a highlight whose anchor start is wrong by +7 and version 0 → `reanchorAll` returns 1 and the stored anchor's start is correct with the current version; a highlight whose text doesn't exist → status `.orphaned`; running `reanchorAll` again changes 0 rows.
- `hitTestNewestFirst`: two overlapping highlights → newest id first at a shared index.
- `syncSkipsOrphans`: an orphaned highlight gets no rendering attribute (inspect with `textLayoutManager.enumerateRenderingAttributes(from:reverse:using:)` over the document range).
- `revealSelectsRange`: `reveal` sets `textView.selectedRange()` to the highlight's range.
- All writing tests end with `FTSIntegrity.check`.

## Acceptance criteria
1. Markdown highlights store the F-07 rich text and re-anchor (moved or orphaned) on open. → tests `newHighlightStoresRichText`, `reanchorMovesAndOrphans`
2. Drawing skips orphans; hits pick the newest. → tests `syncSkipsOrphans`, `hitTestNewestFirst`, `revealSelectsRange`
3. Visual check (user), SPEC F-06 AC1: in a Markdown document, select text with auto-highlight on → highlighted at once; ⌘Z removes it; 1–5 and H work on a selection.
4. Visual check, SPEC F-06 AC3/AC4: resize the window (text reflows) → highlights follow their text; quit and relaunch → same.
5. Visual check: click a highlight → popover (after T62); overlapping highlights: newest on top.

## Out of scope
- PDF text view (Phase 3), popover UI (T62), panel (T63).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-27, implementer pdf-engine Sonnet high (no reworks), reviewer code-reviewer Sonnet medium: APPROVED (conditional on the full unit run). Rendering attributes keep offsets stable, re-anchor once per open and idempotent, reveal syncs first, undo torn down; 31 unit tests on CI. Open: whether Edit > Undo is enabled for a non-editable NSTextView (Mac check, may become a T63 checkpoint FAIL). B6 fixed; B13 added.
