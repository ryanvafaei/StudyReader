import Foundation

/// What one review card shows before and after the reveal (SPEC F-15, F-16; ADR-0022 card display).
/// Pure: the review screen, the themed session and the flashcards view all build their cards with `make`.
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

    static func make(_ item: ReviewCardItem, showOriginal: Bool = false) -> ReviewCardContent {
        let card = item.card
        let highlight = item.highlight

        let front: Body
        let back: Body?
        let source: Body?
        switch card.cardType {
        case .passive:
            front = passiveFront(highlight, showOriginal: showOriginal)
            back = nil
            source = nil
        case .cloze:
            let text = card.answer ?? highlight.editedText ?? highlight.text
            let ranges = ClozeText.normalized(card.clozeRanges ?? [], in: text)
            front = .markdown(ClozeText.front(text, ranges: ranges))
            back = .markdown(ClozeText.back(text, ranges: ranges))
            source = nil
        case .qa:
            front = .markdown(RichTextMarkdown.escape(card.question ?? ""))
            back = .markdown(RichTextMarkdown.escape(card.answer ?? ""))
            source = passiveFront(highlight, showOriginal: showOriginal)
        }

        return ReviewCardContent(
            cardType: card.cardType,
            front: front,
            back: back,
            source: source,
            needsReveal: card.cardType != .passive,
            documentTitle: item.documentTitle,
            pageNumber: highlight.pageIndex.map { $0 + 1 },
            color: highlight.color,
            note: highlight.note,
            tagNames: item.tagNames,
            isEdited: highlight.editedText != nil
        )
    }

    /// The highlight as a passive card shows it: its image, else its excerpt (or the original text with `showOriginal`).
    private static func passiveFront(_ highlight: Highlight, showOriginal: Bool) -> Body {
        if let imagePath = highlight.imagePath {
            return .image(relativePath: imagePath)
        }
        if showOriginal {
            let original = highlight.richText.isEmpty
                ? RichTextMarkdown.escape(highlight.text)
                : highlight.richText
            return .markdown(original)
        }
        return .markdown(highlight.listExcerptMarkdown)
    }
}
