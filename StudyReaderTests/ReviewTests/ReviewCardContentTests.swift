import Testing
import Foundation
@testable import StudyReader

/// Card presentation (T107, ADR-0022 card display). Items are built directly; no database.
@Suite struct ReviewCardContentTests {

    private static let referenceDate = TestData.referenceDate

    private static func highlight(
        text: String,
        richText: String? = nil,
        editedText: String? = nil,
        pageIndex: Int? = nil,
        imagePath: String? = nil
    ) -> Highlight {
        var highlight = TestData.highlight(documentId: "doc-1", text: text, note: "my note")
        highlight.richText = richText ?? text
        highlight.editedText = editedText
        highlight.pageIndex = pageIndex
        if imagePath != nil {
            highlight.kind = .image
            highlight.imagePath = imagePath
        }
        return highlight
    }

    private static func card(
        highlightId: String,
        type: CardType,
        question: String? = nil,
        answer: String? = nil,
        clozeRanges: [[Int]]? = nil
    ) -> ReviewCard {
        ReviewCard(
            id: "card-\(highlightId)",
            highlightId: highlightId,
            cardType: type,
            clozeRanges: clozeRanges,
            question: question,
            answer: answer,
            fsrsCard: "{}",
            dueAt: referenceDate,
            state: .new,
            createdAt: referenceDate
        )
    }

    private static func item(_ card: ReviewCard, _ highlight: Highlight, tags: [String] = []) -> ReviewCardItem {
        ReviewCardItem(
            card: card,
            highlight: highlight,
            documentTitle: "Biology",
            categoryFrequency: .normal,
            tagNames: tags
        )
    }

    @Test func passiveShowsEverythingAtOnce() {
        let highlight = Self.highlight(text: "Plain text", richText: "Plain **text**", pageIndex: 2)
        let passive = Self.card(highlightId: highlight.id, type: .passive)
        let content = ReviewCardContent.make(Self.item(passive, highlight, tags: ["exam", "week"]))

        #expect(content.needsReveal == false)
        #expect(content.front == .markdown("Plain **text**"))
        #expect(content.back == nil)
        #expect(content.source == nil)
        #expect(content.note == "my note")
        #expect(content.tagNames == ["exam", "week"])
        #expect(content.pageNumber == 3)
        #expect(content.documentTitle == "Biology")
        #expect(content.isEdited == false)
    }

    @Test func passiveEditedAndOriginal() {
        let highlight = Self.highlight(text: "orig", richText: "**orig**", editedText: "edited *x*")
        let passive = Self.card(highlightId: highlight.id, type: .passive)

        let shown = ReviewCardContent.make(Self.item(passive, highlight))
        #expect(shown.front == .markdown("edited \\*x\\*"))
        #expect(shown.isEdited)

        let original = ReviewCardContent.make(Self.item(passive, highlight), showOriginal: true)
        #expect(original.front == .markdown("**orig**"))
    }

    @Test func imagePassive() {
        let highlight = Self.highlight(text: "", imagePath: "snapshots/one.png")
        let passive = Self.card(highlightId: highlight.id, type: .passive)
        let content = ReviewCardContent.make(Self.item(passive, highlight))
        #expect(content.front == .image(relativePath: "snapshots/one.png"))
        #expect(content.needsReveal == false)
    }

    @Test func clozeUsesItsOwnText() {
        let highlight = Self.highlight(text: "original", editedText: "new")
        let cloze = Self.card(
            highlightId: highlight.id,
            type: .cloze,
            answer: "old text with term",
            clozeRanges: [[14, 4]]
        )
        let content = ReviewCardContent.make(Self.item(cloze, highlight))

        #expect(content.needsReveal)
        #expect(content.front == .markdown("old text with \\[…\\]"))
        #expect(content.back == .markdown("old text with **term**"))
        #expect(content.source == nil)
        #expect(content.isEdited)
    }

    @Test func qaHidesTheAnswer() {
        let highlight = Self.highlight(text: "ATP is energy")
        let qa = Self.card(
            highlightId: highlight.id,
            type: .qa,
            question: "What is *ATP*?",
            answer: "Energy [currency]"
        )
        let content = ReviewCardContent.make(Self.item(qa, highlight))

        #expect(content.needsReveal)
        #expect(content.front == .markdown("What is \\*ATP\\*?"))
        #expect(content.back == .markdown("Energy \\[currency\\]"))
        #expect(content.source == .markdown("ATP is energy"))
    }
}
