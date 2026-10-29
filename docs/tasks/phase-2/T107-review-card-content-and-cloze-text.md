# T107: ReviewCardContent and ClozeText

- **Phase:** 2 (E2.2 Daily review, E2.3 Mastery; SPEC F-15 card front, F-16 cloze display, F-18 "Show original")
- **Agent:** review-engine
- **Depends on:** T102 (`ReviewCardItem`)
- **ADRs:** **ADR-0021** (cloze text lives in `answer`), **ADR-0022** (what a card shows before and after reveal), ARCHITECTURE §10.3
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 6.

## Goal
Pure presentation for one card, so the review screen, the themed session and the flashcards view all show cards the same way: what the front shows, what the reveal adds, and whether a reveal is needed. Includes the cloze text helper (front with `[…]`, back with the hidden words emphasised).

## Files to touch
- `StudyReader/Features/Review/Mastery/ClozeText.swift` (new: `ClozeRange`, `ClozeText`)
- `StudyReader/Features/Review/Sessions/ReviewCardContent.swift` (new)
- `StudyReaderTests/ReviewTests/ClozeTextTests.swift` (new)
- `StudyReaderTests/ReviewTests/ReviewCardContentTests.swift` (new)

## Interfaces to produce
```swift
// ClozeText.swift
/// One hidden span: UTF-16 offsets into the cloze card's text (reviewCard.answer, ADR-0021).
struct ClozeRange: Codable, Sendable, Hashable {
    var location: Int
    var length: Int
    var pair: [Int] { [location, length] }       // reviewCard.clozeRanges element
}

enum ClozeText {
    /// Markdown for the hidden span (renders as "[…]").
    static let placeholderMarkdown = "\\[…\\]"
    /// Keeps only pairs with exactly 2 values, location >= 0, length > 0, location + length <= text.utf16.count;
    /// sorts by location; merges overlapping ranges (not merely touching ones).
    static func normalized(_ pairs: [[Int]], in text: String) -> [ClozeRange]
    /// Text outside the ranges through RichTextMarkdown.escape; each range replaced by placeholderMarkdown.
    static func front(_ text: String, ranges: [ClozeRange]) -> String
    /// Text outside the ranges escaped; each range's text escaped and wrapped in "**…**", with any leading or trailing
    /// whitespace of the range moved outside the markers (CommonMark ignores "** word**"). A whitespace-only range is
    /// written without markers.
    static func back(_ text: String, ranges: [ClozeRange]) -> String
}

// ReviewCardContent.swift
struct ReviewCardContent: Sendable, Equatable {
    enum Body: Sendable, Equatable {
        case markdown(String)                 // F-07 Markdown subset, shown with RichTextView
        case image(relativePath: String)      // image highlight; the view resolves it with FileStore
    }
    var cardType: CardType
    var front: Body
    /// nil for passive cards (everything is on the front).
    var back: Body?
    /// Q&A only: the highlight itself (text or image), shown after the reveal under the answer.
    var source: Body?
    var needsReveal: Bool                     // cardType != .passive
    var documentTitle: String
    var pageNumber: Int?                      // highlight.pageIndex + 1
    var color: HighlightColor
    var note: String                          // raw note; the view renders it with NoteMarkdownView
    var tagNames: [String]
    var isEdited: Bool                        // highlight.editedText != nil

    static func make(_ item: ReviewCardItem, showOriginal: Bool = false) -> ReviewCardContent
}
```
`make` rules:
- **Passive:** `front` = `.image(relativePath:)` when the highlight has an `imagePath`; otherwise `.markdown(highlight.listExcerptMarkdown)` (existing extension in `HighlightsBrowserModel.swift`: edited text escaped, else rich text, else escaped text). With `showOriginal == true`: `richText` if not empty, else `RichTextMarkdown.escape(text)`. `back` nil, `source` nil.
- **Cloze:** `text = card.answer ?? highlight.editedText ?? highlight.text`; `ranges = ClozeText.normalized(card.clozeRanges ?? [], in: text)`; `front = .markdown(ClozeText.front(text, ranges:))`, `back = .markdown(ClozeText.back(text, ranges:))`, `source` nil.
- **Q&A:** `front = .markdown(RichTextMarkdown.escape(card.question ?? ""))`, `back = .markdown(RichTextMarkdown.escape(card.answer ?? ""))`, `source` = the passive front for this highlight (respecting `showOriginal`).
- The other fields come from the item for every type.

## Acceptance criteria
1. `ClozeTextTests/frontAndBack`: text "The mitochondria produce ATP.", pairs [[4, 12]] → front `"The \\[…\\] produce ATP."`, back `"The **mitochondria** produce ATP."`. Two ranges ("mitochondria", "ATP") → two placeholders / two bold spans.
2. `ClozeTextTests/whitespaceMovesOutsideMarkers`: pairs [[3, 13]] (" mitochondria") → back `"The **mitochondria** produce ATP."`.
3. `ClozeTextTests/normalizationDropsInvalidRanges` (table): `[[-1, 2]]`, `[[0, 0]]`, `[[0]]`, `[[20, 50]]` → `[]`; `[[10, 3], [4, 12]]` → sorted and merged into one range 4…16; touching `[[0, 3], [3, 2]]` stays two ranges. Offsets are UTF-16: "naïve café" with "café" at UTF-16 6…10 works; a pair past `utf16.count` is dropped.
4. `ClozeTextTests/escapesMarkdown`: text "a *b* [c]" with "b" hidden → front `"a \\*\\[…\\]\\* \\[c\\]"`.
5. `ReviewCardContentTests` (build `ReviewCardItem` values directly, no database):
   - `passiveShowsEverythingAtOnce`: `needsReveal == false`, `back == nil`, note and tags filled, `pageNumber == pageIndex + 1`.
   - `passiveEditedAndOriginal`: with `editedText` the front is the escaped edited text and `isEdited`; `showOriginal: true` shows `richText`.
   - `imagePassive`: front `.image(relativePath:)`.
   - `clozeUsesItsOwnText`: `answer` = "old text with term", highlight `editedText` = "new" → front/back built from "old text with term".
   - `qaHidesTheAnswer`: `needsReveal`, front = escaped question, back = escaped answer, `source` = the highlight.
6. `./scripts/test.sh StudyReaderTests/ClozeTextTests StudyReaderTests/ReviewCardContentTests` passes; `./scripts/build.sh` succeeds.

## Out of scope
- Views. Creating or editing cloze cards (T115, T117).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
