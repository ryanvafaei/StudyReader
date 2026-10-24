import Foundation
import GRDB
import Markdown
import FSRS
import SwiftUI
import Testing
@testable import StudyReader

@Suite struct NameClashTests {
    @Test func appTypesResolveUnqualified() {
        let types: [Any.Type] = [
            LibraryDocument.self,
            DocumentCategory.self,
            DocumentText.self,
            Highlight.self,
            LibraryTag.self,
            HighlightTag.self,
            DocumentTag.self,
            DocumentNote.self,
            ReviewCard.self,
            ReviewLogEntry.self,
            ThemedReview.self,
            ExportTarget.self,
            HighlightEmbedding.self,
            HighlightAnchor.self,
            PDFAnchor.self,
            TextAnchor.self,
            ImageAnchor.self,
            ReviewCardState.self,
            CardType.self,
            HighlightColor.self,
            ReviewFrequency.self,
        ]
        #expect(types.count == 21)
    }

    @Test func renamedTypesKeepStoredValues() throws {
        #expect(ReviewCardState.allCases.map(\.rawValue) == ["new", "learning", "review", "relearning"])

        let anchor = HighlightAnchor.text(TextAnchor(
            start: 1, length: 2, text: "ab", prefix: "", suffix: "", sourceVersion: 1))
        let data = try JSONEncoder().encode(anchor)
        let object = try JSONSerialization.jsonObject(with: data)
        let root = try #require(object as? [String: Any])

        #expect(root["type"] as? String == "text")
        #expect(root.keys.sorted() == ["text", "type"])
    }
}
