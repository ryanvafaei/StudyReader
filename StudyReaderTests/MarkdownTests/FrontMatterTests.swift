import Testing
@testable import StudyReader

@Suite struct FrontMatterTests {
    @Test func parsesTitleAndAuthor() throws {
        let markdown = try MarkdownFixtures.string("front-matter")
        let result = FrontMatterParser.split(markdown)
        #expect(result.frontMatter.title == "Gradient Descent Notes")
        #expect(result.frontMatter.author == "Ada Lovelace")
        #expect(result.body.hasPrefix("\n# Gradient Descent"))
        #expect(!result.body.contains("course:"))
    }

    @Test func variants() {
        // Quoted values keep their inner colon; one pair of quotes is removed.
        let quoted = FrontMatterParser.split("---\ntitle: \"A: B\"\nauthor: 'Ada'\n---\nBody")
        #expect(quoted.frontMatter == FrontMatter(title: "A: B", author: "Ada"))
        #expect(quoted.body == "Body")

        // "..." closes the front matter too.
        let dots = FrontMatterParser.split("---\ntitle: Dots\n...\nBody")
        #expect(dots.frontMatter.title == "Dots")
        #expect(dots.body == "Body")

        // CRLF line endings behave like LF.
        let crlf = FrontMatterParser.split("---\r\ntitle: Windows\r\nauthor: Grace\r\n---\r\nBody")
        #expect(crlf.frontMatter == FrontMatter(title: "Windows", author: "Grace"))
        #expect(crlf.body == "Body")

        // A UTF-8 BOM before the opening line is skipped.
        let bom = FrontMatterParser.split("\u{FEFF}---\ntitle: Bom\n---\nBody")
        #expect(bom.frontMatter.title == "Bom")
        #expect(bom.body == "Body")

        // No closing line: unchanged body, empty front matter.
        let unclosed = "---\ntitle: Open\nBody without closing"
        let open = FrontMatterParser.split(unclosed)
        #expect(open.frontMatter == FrontMatter())
        #expect(open.body == unclosed)

        // "---" not on the first line: unchanged.
        let late = "# Heading\n---\ntitle: Late\n---\nBody"
        let lateResult = FrontMatterParser.split(late)
        #expect(lateResult.frontMatter == FrontMatter())
        #expect(lateResult.body == late)

        // Empty value becomes nil.
        let empty = FrontMatterParser.split("---\ntitle:\nauthor: \"\"\n---\nBody")
        #expect(empty.frontMatter == FrontMatter(title: nil, author: nil))
        #expect(empty.body == "Body")
    }
}
