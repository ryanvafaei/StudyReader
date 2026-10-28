import Foundation
import Testing
@testable import StudyReader

@Suite("NotePreview")
struct NotePreviewTests {
    @Test
    func headingsListsRulesAndLineBreaks() {
        let blocks = NotePreviewBlock.blocks("# Title\n\n- a\n  - b\n\n1. one\n2. two\n\n---\n\nline one\nline two")
        let plain = blocks.map { String($0.text.characters) }

        #expect(plain.first == "Title")
        #expect(plain.contains("\u{2022} a"))
        #expect(plain.contains("\u{2022} b"))
        #expect(plain.contains("1. one"))
        #expect(plain.contains("2. two"))
        #expect(blocks.filter(\.isRule).count == 1)
        #expect(plain.last == "line one\nline two")

        let indent = { (text: String) in blocks.first { String($0.text.characters) == text }?.indent }
        #expect(indent("\u{2022} a") == 0)
        #expect(indent("\u{2022} b") == 1)
        #expect(indent("1. one") == 0)
    }

    @Test
    func multiParagraphListItemHasOneBullet() {
        let blocks = NotePreviewBlock.blocks("- first\n\n  second")
        let bulleted = blocks.filter { String($0.text.characters).hasPrefix("\u{2022}") }

        #expect(bulleted.count == 1)
        #expect(blocks.count == 2)
    }
}
