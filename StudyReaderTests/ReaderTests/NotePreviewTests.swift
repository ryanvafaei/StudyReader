import Foundation
import Testing
@testable import StudyReader

@Suite("NotePreview")
struct NotePreviewTests {
    @Test
    func headingsListsRulesAndLineBreaks() {
        let blocks = NoteMarkdown.blocks("# Title\n\n- a\n  - b\n\n1. one\n2. two\n\n---\n\nline one\nline two")
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
        let blocks = NoteMarkdown.blocks("- first\n\n  second")
        let bulleted = blocks.filter { String($0.text.characters).hasPrefix("\u{2022}") }

        #expect(bulleted.count == 1)
        #expect(blocks.count == 2)
    }

    @Test
    func headingLevelsAndStyling() {
        let blocks = NoteMarkdown.blocks("# One\n\n## Two\n\n### Three\n\n#### Four\n\nplain")
        #expect(blocks.map(\.headingLevel) == [1, 2, 3, 4, 0])
        #expect(blocks.map { String($0.text.characters) } == ["One", "Two", "Three", "Four", "plain"])
        #expect(blocks.allSatisfy { !String($0.text.characters).contains("#") })

        #expect(NoteMarkdown.headingFont(level: 1, style: .regular) == .title2.bold())
        #expect(NoteMarkdown.headingFont(level: 2, style: .regular) == .title3.bold())
        #expect(NoteMarkdown.headingFont(level: 3, style: .regular) == .headline)
        #expect(NoteMarkdown.headingFont(level: 4, style: .regular) == .headline)
        #expect(NoteMarkdown.headingFont(level: 1, style: .compact) == .title3.bold())
        #expect(NoteMarkdown.headingFont(level: 2, style: .compact) == .headline)
        #expect(NoteMarkdown.headingFont(level: 3, style: .compact) == .callout.bold())
        #expect(NoteMarkdown.headingFont(level: 0, style: .regular) == nil)
        #expect(NoteMarkdown.headingFont(level: 0, style: .compact) == nil)
        let regular = (1...3).map { NoteMarkdown.headingFont(level: $0, style: .regular) }
        #expect(regular[0] != regular[1] && regular[1] != regular[2] && regular[0] != regular[2])
    }

    @Test
    func hashTagIsNotAHeading() {
        let tags = NoteMarkdown.blocks("#todo review\n#exam")
        #expect(tags.count == 1)
        #expect(tags.first?.headingLevel == 0)
        let text = tags.first.map { String($0.text.characters) } ?? ""
        #expect(text.contains("#todo review"))
        #expect(text.contains("#exam"))

        let heading = NoteMarkdown.blocks("# todo")
        #expect(heading.count == 1)
        #expect(heading.first?.headingLevel == 1)
        #expect(heading.first.map { String($0.text.characters) } == "todo")
    }

    @Test
    func inlineMarkdownInNotes() {
        let blocks = NoteMarkdown.blocks("*it* and **bold**")
        #expect(blocks.count == 1)
        guard let text = blocks.first?.text else { return }
        #expect(String(text.characters) == "it and bold")
        let intents = text.runs.map { (String(text[$0.range].characters), $0.inlinePresentationIntent ?? []) }
        #expect(intents.first { $0.0 == "it" }?.1.contains(.emphasized) == true)
        #expect(intents.first { $0.0 == "bold" }?.1.contains(.stronglyEmphasized) == true)
    }
}
