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

    private func handBuilt(_ string: String, _ entries: [MarkdownSourceMap.Entry], range: NSRange? = nil) -> String {
        RichTextMarkdown.markdown(
            for: range ?? fullRange(string), in: string, sourceMap: MarkdownSourceMap(entries: entries))
    }

    private func entry(_ location: Int, _ length: Int, _ traits: InlineTraits, link: String? = nil) -> MarkdownSourceMap.Entry {
        MarkdownSourceMap.Entry(range: NSRange(location: location, length: length), traits: traits, linkDestination: link)
    }

    @Test(.timeLimit(.minutes(1)))
    func adjacentLinkRunsFormOneLink() {
        let destination = "https://x.org"
        let result = handBuilt("a b", [
            entry(0, 1, [.link, .bold], link: destination),
            entry(1, 2, .link, link: destination),
        ])
        #expect(result == "[**a** b](https://x.org)")
        #expect(result.components(separatedBy: "](").count == 2)

        // Different destinations, or a gap between the runs, stay separate links.
        #expect(handBuilt("ab", [
            entry(0, 1, .link, link: "https://x.org"),
            entry(1, 1, .link, link: "https://y.org"),
        ]) == "[a](https://x.org)[b](https://y.org)")
        #expect(handBuilt("a-b", [
            entry(0, 1, .link, link: destination),
            entry(2, 1, .link, link: destination),
        ]) == "[a](https://x.org)-[b](https://x.org)")

        // Whitespace at the ends of the whole link stays outside the brackets.
        #expect(handBuilt(" a b ", [
            entry(0, 3, .link, link: destination),
            entry(3, 2, [.link, .italic], link: destination),
        ]) == " [a *b*](https://x.org) ")
    }

    @Test(.timeLimit(.minutes(1)))
    func entriesBeyondTheSelectionAreSkipped() {
        let result = handBuilt("one two three", [
            entry(0, 3, .bold),
            entry(4, 3, .italic),
            entry(8, 5, .bold),
        ], range: NSRange(location: 0, length: 7))
        #expect(result == "**one** *two*")
    }

    @Test(.timeLimit(.minutes(1)))
    func emphasisMovesPunctuationOutside() {
        #expect(handBuilt("a\"x\"b", [entry(1, 3, .bold)]) == "a\"**x**\"b")
        #expect(handBuilt("(x)", [entry(0, 3, .italic)]) == "(*x*)")
        #expect(handBuilt("a \"x!\" b", [entry(2, 4, [.bold, .italic])]) == "a \"***x***!\" b")
        #expect(handBuilt("a!b", [entry(1, 1, .bold)]) == "a!b")
        #expect(handBuilt("a!!b", [entry(1, 2, [.bold, .italic])]) == "a!!b")
        // The moved punctuation is escaped, and stays inside a link's brackets.
        #expect(handBuilt("*x*", [entry(0, 3, .bold)]) == "\\***x**\\*")
        #expect(handBuilt("\"x\"", [entry(0, 3, [.bold, .link], link: "https://x.org")]) == "[\"**x**\"](https://x.org)")
        // Code spans keep their content.
        #expect(handBuilt("(x)", [entry(0, 3, .code)]) == "`(x)`")
    }

    @Test(.timeLimit(.minutes(1)))
    func destinationEscaping() {
        let result = handBuilt("t", [entry(0, 1, .link, link: "https://x.org/a b(c)")])
        #expect(result == "[t](https://x.org/a%20b\\(c\\))")
    }

    @Test(.timeLimit(.minutes(1)))
    func boldItalicCodePaddingAndPartialLink() {
        #expect(handBuilt("x", [entry(0, 1, [.bold, .italic])]) == "***x***")
        #expect(handBuilt("`x", [entry(0, 2, .code)]) == "`` `x ``")
        #expect(handBuilt("x`", [entry(0, 2, .code)]) == "`` x` ``")

        let linkText = "link text"
        let selection = (linkText as NSString).range(of: "link")
        #expect(handBuilt(linkText, [entry(0, 9, .link, link: "https://x.org")], range: selection) == "[link](https://x.org)")
    }

    @Test(.timeLimit(.minutes(1)))
    func attachmentsDroppedAndPlainEscaped() {
        let string = "x*\u{FFFC}y"
        let result = RichTextMarkdown.markdown(
            for: fullRange(string), in: string, sourceMap: MarkdownSourceMap(entries: []))
        #expect(result == "x\\*y")
    }
}
