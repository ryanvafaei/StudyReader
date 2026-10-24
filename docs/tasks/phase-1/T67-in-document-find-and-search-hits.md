# T67: In-document find and search-hit navigation

- **Phase:** 1 (E1.6: F-12 in-document find, "clicking a result opens the document at the location")
- **Agent:** pdf-engine
- **Depends on:** T59, T60, T66
- **ADRs:** docs/decisions/0017-reader-windows-and-commands.md, ARCHITECTURE §8 (last two bullets)
- **Visual check needed:** yes

## Goal
⌘F while reading searches only the open document and steps through matches: a find bar for the PDF view (PDFKit find) and the NSTextView find bar for Markdown. And `.searchHit(unitIndex:query:)` locations from global search open at the right place with the first match selected.

## Files to touch
- `StudyReader/Features/Reader/PDF/PDFFindController.swift` (new)
- `StudyReader/Features/Reader/PDF/PDFFindBar.swift` (new: SwiftUI bar)
- `StudyReader/Features/Reader/PDF/PDFReaderController.swift`, `PDFReaderView.swift` (modify)
- `StudyReader/Features/Reader/Text/TextReaderController.swift`, `StudyReader/Features/Reader/Markdown/MarkdownReaderView.swift` (modify)
- `StudyReaderTests/ReaderTests/FindTests.swift` (new)

## Interfaces to produce
```swift
@MainActor @Observable
final class PDFFindController {
    init(pdfView: StudyPDFView)
    var isVisible = false
    var query = ""
    private(set) var matchCount = 0
    private(set) var currentIndex: Int? = nil       // 0-based
    /// document.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive]); selects and reveals
    /// the first match at or after the current page.
    func search()
    func next(); func previous()                     // wrap around
    func close()                                     // hides the bar, clears highlighted matches
    /// First case/diacritic-insensitive match of `term` on page `pageIndex`, selected and scrolled to; false if none.
    @discardableResult func selectFirstMatch(of term: String, onPage pageIndex: Int) -> Bool
}

extension TextReaderController {
    /// First case/diacritic-insensitive match of `term` at or after `offset` (wrapping to the start); selects and
    /// scrolls to it. false if none.
    @discardableResult func selectFirstMatch(of term: String, from offset: Int) -> Bool
}
```
Behaviour:
- PDF: `engineActions.findInDocument` shows `PDFFindBar` at the top of the PDF view (text field, "n of m", previous/next buttons, Done); Return = next, ⇧Return = previous, Escape = close. Matches are shown with `pdfView.highlightedSelections` and the current one as `currentSelection`.
- Markdown: `findInDocument` calls `textView.performTextFinderAction(NSTextFinder.Action.showFindInterface)` (`usesFindBar` is on from T55).
- `.searchHit(unitIndex, query)` pending location:
  - term = `SearchQueryParser.firstPositiveTerm(in: query)`; nil → just go to the unit.
  - PDF: `go(toPage: unitIndex)` then `selectFirstMatch(of: term, onPage: unitIndex)`. The term may span a line break in the PDF; if no match, keep the page.
  - Markdown: the section start comes from the renderer (`RenderedMarkdown.sections[unitIndex].location`, kept by `MarkdownReaderView` since T55/T60); `selectFirstMatch(of: term, from: sectionStart)`; out-of-range unit → start of document.
  - Then `model.consumeLocation()`.
- Search terms come from user input; use them only as plain search strings (no regex).

## Tests (`FindTests`, `@MainActor`)
- `pdfFindCountsAndSteps`: `plainMultiPage(pageCount: 3)` in a `StudyPDFView`; query "fox" → `matchCount == 30` (10 lines × 3 pages); `next()` advances `currentIndex`; `previous()` from 0 wraps to 29.
- `pdfSelectFirstMatchOnPage`: `selectFirstMatch(of: "line 5", onPage: 2)` → true and `currentSelection?.pages.first` is page 2; "zebra" → false.
- `textSelectFirstMatch`: Markdown `all-elements.md` rendered; `selectFirstMatch(of: "item", from: 0)` selects the first "item" (case-insensitive: matches "Unordered item one"'s "item"); from an offset past the last match wraps to the first.
- `searchHitLocationConsumed`: set `model.navigate(to: .searchHit(unitIndex: 1, query: "\"page 2 line 3\""))` on a loaded PDF reader → after handling, the current page is 1, the selection contains "Page 2 line 3", `model.pendingLocation == nil`.

## Acceptance criteria
1. PDF find counts and steps through matches; first-match selection works for pages and text offsets. → tests `FindTests/*`
2. Visual check (user): in a PDF, ⌘F shows the find bar; typing a word shows "1 of N"; Return/⇧Return step through matches with the current one selected; Escape closes. In a Markdown document, ⌘F shows the standard find bar.
3. Visual check: from global search, clicking a PDF page result opens the document on that page with the word selected; a Markdown section result scrolls to the first match in that section.

## Out of scope
- Global search UI (T66), the PDF text view (Phase 3).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
