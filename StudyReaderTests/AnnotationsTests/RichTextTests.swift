import Foundation
import Testing
@testable import StudyReader

@Suite("RichText")
struct RichTextTests {
    private func render(_ markdown: String) -> RenderedMarkdown {
        MarkdownRenderer.render(MarkdownDocumentSource(markdown: markdown, documentId: nil, fileStore: nil))
    }

    private func fullRange(_ string: String) -> NSRange {
        NSRange(location: 0, length: (string as NSString).length)
    }

    private func range(of needle: String, in string: String) throws -> NSRange {
        let found = (string as NSString).range(of: needle)
        try #require(found.location != NSNotFound, "missing \(needle)")
        return found
    }

    @Test(.timeLimit(.minutes(1)))
    func markdownSelection() throws {
        let rendered = render(try MarkdownFixtures.string("rich-inline"))
        let result = RichTextMarkdown.markdown(
            for: fullRange(rendered.string), in: rendered.string, sourceMap: rendered.sourceMap)
        #expect(result == "a **bold** and *italic* word with `code`")
    }

    @Test(.timeLimit(.minutes(1)))
    func partialSelection() throws {
        let rendered = render(try MarkdownFixtures.string("rich-inline"))
        let selection = try range(of: "old and ital", in: rendered.string)
        let result = RichTextMarkdown.markdown(for: selection, in: rendered.string, sourceMap: rendered.sourceMap)
        #expect(result == "**old** and *ital*")
    }

    @Test(.timeLimit(.minutes(1)))
    func linksAndNesting() {
        let source = "See [**Apple**](https://www.apple.com) now"
        let rendered = render(source)
        let result = RichTextMarkdown.markdown(
            for: fullRange(rendered.string), in: rendered.string, sourceMap: rendered.sourceMap)
        #expect(result == source)
    }

    @Test(.timeLimit(.minutes(1)))
    func escapesPlainText() {
        #expect(RichTextMarkdown.escape("a*b_c [x] `y` \\") == "a\\*b\\_c \\[x\\] \\`y\\` \\\\")
        #expect(RichTextMarkdown.escape("line one\nline two") == "line one\nline two")

        let sample = "a*b_c [x] `y` \\ end"
        let parsed = try? AttributedString(markdown: RichTextMarkdown.escape(sample))
        #expect(parsed.map { String($0.characters) } == sample)
    }

    @Test(.timeLimit(.minutes(1)))
    func codeWithBacktick() {
        let rendered = render("run ``a`b`` now")
        let result = RichTextMarkdown.markdown(
            for: fullRange(rendered.string), in: rendered.string, sourceMap: rendered.sourceMap)
        #expect(result == "run ``a`b`` now")
    }

    @Test(.timeLimit(.minutes(1)))
    func whitespaceOutsideMarkers() throws {
        let rendered = render(try MarkdownFixtures.string("rich-inline"))
        let selection = try range(of: " bold", in: rendered.string)
        let result = RichTextMarkdown.markdown(for: selection, in: rendered.string, sourceMap: rendered.sourceMap)
        #expect(result == " **bold**")

        let string = "a bold c"
        let map = MarkdownSourceMap(entries: [
            MarkdownSourceMap.Entry(range: NSRange(location: 1, length: 6), traits: .bold, linkDestination: nil)
        ])
        let handBuilt = RichTextMarkdown.markdown(for: fullRange(string), in: string, sourceMap: map)
        #expect(handBuilt == "a **bold** c")
    }

    @Test(.timeLimit(.minutes(1)))
    func attachmentsDroppedAndPlainEscaped() {
        let string = "x*\u{FFFC}y"
        let result = RichTextMarkdown.markdown(
            for: fullRange(string), in: string, sourceMap: MarkdownSourceMap(entries: []))
        #expect(result == "x\\*y")
    }
}
