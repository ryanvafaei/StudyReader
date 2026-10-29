import Testing
import Foundation
@testable import StudyReader

@MainActor
@Suite struct ReviewEditDraftTests {

    private static func highlight(text: String, editedText: String?) -> Highlight {
        var highlight = TestData.highlight(documentId: "doc-1", text: text)
        highlight.editedText = editedText
        return highlight
    }

    @Test func startsWithEditedOrOriginal() {
        let edited = ReviewEditDraft(highlight: Self.highlight(text: "A", editedText: "B"))
        #expect(edited.text == "B")
        let plain = ReviewEditDraft(highlight: Self.highlight(text: "A", editedText: nil))
        #expect(plain.text == "A")
    }

    @Test func valueToStoreRules() {
        let draft = ReviewEditDraft(highlight: Self.highlight(text: "Original", editedText: nil))
        #expect(!draft.isChanged)
        draft.text = "   \n"
        #expect(draft.isChanged)
        #expect(draft.valueToStore == nil)
        draft.text = "Original"
        #expect(!draft.isChanged)
        #expect(draft.valueToStore == nil)
        draft.text = "New"
        #expect(draft.isChanged)
        #expect(draft.valueToStore == "New")
    }
}
