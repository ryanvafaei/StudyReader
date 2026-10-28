import Foundation
import Testing
@testable import StudyReader

private final class ExportGoldenBundleToken {}

enum ExportGoldens {
    /// Bundle(for:).url(forResource: name, withExtension: "md", subdirectory: "Fixtures/golden/export").
    static func string(_ name: String) throws -> String {
        guard let url = Bundle(for: ExportGoldenBundleToken.self).url(
            forResource: name,
            withExtension: "md",
            subdirectory: "Fixtures/golden/export"
        ) else {
            throw MarkdownFixtureError.missing(name)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

@Suite("ExportRenderer")
struct ExportRendererTests {
    static let generatedAt = Date(timeIntervalSince1970: 1_792_850_700)   // 2026-10-24 14:05 UTC
    static let utc = TimeZone(identifier: "UTC") ?? .gmt
    static let labels = HighlightColor.allCases.map { SettingsStore.defaultColorLabel(for: $0) }

    static func highlight(
        _ id: String,
        color: HighlightColor,
        kind: HighlightKind = .text,
        page: Int?,
        body: String,
        note: String = "",
        tags: [String] = [],
        position: Double
    ) -> ExportHighlight {
        ExportHighlight(
            id: id, documentId: "d1", kind: kind, color: color, pageIndex: page,
            body: body, note: note, tagNames: tags, positionKey: position
        )
    }

    /// The content of the golden files.
    static func lectureContent() -> ExportContent {
        ExportContent(scopeName: "ML1 Lecture 3", documents: [
            ExportDocument(
                id: "d1",
                title: "Lecture 3: Gradient Descent",
                author: "Ada Lovelace",
                categoryName: "Lecture slides",
                documentNote: "Exam covers sections 2–4.",
                highlights: [
                    highlight("h1", color: .yellow, page: 0, body: "The **gradient** points uphill.",
                              note: "Negate it to descend.", tags: ["exam", "ml"], position: 1),
                    highlight("h2", color: .blue, kind: .image, page: 2, body: "", position: 2),
                    highlight("h3", color: .green, page: 4, body: "Learning rate *η*",
                              note: "Line one\n\nLine two", tags: ["ml"], position: 3),
                ]
            ),
        ])
    }

    /// The content of the note-rule golden files (T87).
    static func notesContent() -> ExportContent {
        ExportContent(scopeName: "Notes", documents: [
            ExportDocument(
                id: "d1", title: "Notes Doc", author: "", categoryName: "Paper",
                documentNote: "# Plan\n#todo review *italic* and **bold**\n\n- first\n- second\n\n## Details\nUse <b> | x ~~y~~ and `a|b`",
                highlights: [
                    highlight("h1", color: .yellow, page: 0, body: "Plain body.",
                              note: "# Why\n#todo check **bold** and *italic*\n- one\n- two", tags: ["exam"], position: 1),
                ]
            ),
        ])
    }

    static func render(_ content: ExportContent, _ options: ExportOptions = ExportOptions()) -> String {
        ExportRenderer.render(content, options: options, colorLabels: labels, generatedAt: generatedAt, timeZone: utc)
    }

    @Test(.timeLimit(.minutes(1)))
    func byDocumentAllOptions() throws {
        #expect(Self.render(Self.lectureContent()) == (try ExportGoldens.string("by-document-all-options")))
    }

    @Test(.timeLimit(.minutes(1)))
    func byTagAllOptions() throws {
        let output = Self.render(Self.lectureContent(), ExportOptions(groupBy: .tag))
        #expect(output == (try ExportGoldens.string("by-tag-all-options")))
    }

    /// SPEC F-09 AC4
    @Test(.timeLimit(.minutes(1)))
    func notesByDocument() throws {
        #expect(Self.render(Self.notesContent()) == (try ExportGoldens.string("notes-by-document")))
    }

    /// SPEC F-09 AC4
    @Test(.timeLimit(.minutes(1)))
    func notesByTag() throws {
        let output = Self.render(Self.notesContent(), ExportOptions(groupBy: .tag))
        #expect(output == (try ExportGoldens.string("notes-by-tag")))
    }

    /// SPEC F-09 AC4, ADR-0007 amendment 2026-10-28
    @Test(.timeLimit(.minutes(1)))
    func noteRules() {
        func note(_ text: String, _ headings: ExportMarkdownSafety.NoteHeadings) -> String {
            ExportMarkdownSafety.note(text, headings: headings)
        }
        // Headings, demoted
        #expect(note("# A", .demoted) == "#### A")
        #expect(note("## A", .demoted) == "#### A")
        #expect(note("### A", .demoted) == "#### A")
        #expect(note("#### A", .demoted) == "#### A")
        #expect(note("##### A", .demoted) == "##### A")
        #expect(note("#\tA", .demoted) == "#### A")
        // Headings, bold; closing sequence; leading spaces
        #expect(note("# A", .bold) == "**A**")
        #expect(note("### A ###", .bold) == "**A**")
        #expect(note("   ## A", .bold) == "**A**")
        // Empty heading text, and a line-start # that isn't a heading
        #expect(note("# ##", .demoted) == "\\# ##")
        #expect(note("#todo", .bold) == "\\#todo")
        #expect(note("##x", .demoted) == "\\##x")
        #expect(note("#", .demoted) == "\\#")
        #expect(note("####### A", .demoted) == "\\####### A")
        // Untouched
        #expect(note("a #todo b", .bold) == "a #todo b")
        #expect(note("    # code", .demoted) == "    # code")
        // Inline escapes (also inside heading text), code spans, existing escapes
        #expect(note("# a<b", .demoted) == "#### a\\<b")
        #expect(note("<b> | ~~s~~", .bold) == "\\<b> \\| \\~\\~s\\~\\~")
        #expect(note("`a<b|c~d`", .bold) == "`a<b|c~d`")
        #expect(note("\\# kept \\< kept", .bold) == "\\# kept \\< kept")
        #expect(note("```\n# not a heading\n```", .demoted) == "```\n# not a heading\n```")
        // Kept as written
        #expect(note("- item\n1. one\n> quote\n*it* **b** [l](http://x.y) & !", .bold)
            == "- item\n1. one\n> quote\n*it* **b** [l](http://x.y) & !")
        // Line ends, empty input
        #expect(note("a\r\n# b", .demoted) == "a\n#### b")
        #expect(note("", .bold) == "")
    }

    /// SPEC F-09 AC4: an indented or blank-line-led document note is still demoted, not exported as a raw heading.
    @Test(.timeLimit(.minutes(1)), arguments: [
        "    # Big", "\t# Big", "\n  \n    # Big", "  \t \n\t# Big\n", "\r\n    # Big",
    ])
    func indentedDocumentNoteHeadingIsDemoted(note: String) {
        let content = ExportContent(scopeName: "S", documents: [
            ExportDocument(
                id: "d1", title: "Doc", author: "", categoryName: "Paper", documentNote: note,
                highlights: [Self.highlight("h1", color: .yellow, page: 0, body: "x", position: 1)]
            ),
        ])
        for groupBy in [ExportGroupBy.document, .tag] {
            let output = Self.render(content, ExportOptions(groupBy: groupBy))
            let lines = output.components(separatedBy: "\n")
            #expect(lines.contains("#### Big"))
            #expect(!lines.contains { $0.hasPrefix("# Big") || $0.trimmingCharacters(in: .whitespaces).hasPrefix("# Big") })
            #expect(lines.filter { $0.hasPrefix("# ") } == ["# StudyReader – S"])
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func byDocumentMinimal() throws {
        let options = ExportOptions(includeNotes: false, includeDocumentNotes: false, includeImages: false)
        #expect(Self.render(Self.lectureContent(), options) == (try ExportGoldens.string("by-document-minimal")))
    }

    @Test(.timeLimit(.minutes(1)))
    func emptyScope() throws {
        let content = ExportContent(scopeName: "All highlights", documents: [])
        #expect(Self.render(content) == (try ExportGoldens.string("empty")))
    }

    /// SPEC F-09 AC2
    @Test(.timeLimit(.minutes(1)))
    func includesNotes() {
        let on = Self.render(Self.lectureContent())
        #expect(on.contains("- Note: Negate it to descend."))
        #expect(on.contains("Exam covers sections 2–4."))

        let off = Self.render(Self.lectureContent(), ExportOptions(includeNotes: false, includeDocumentNotes: false))
        #expect(!off.contains("Negate it to descend."))
        #expect(!off.contains("Exam covers sections 2–4."))
        #expect(!off.contains("### Document note"))
    }

    @Test(.timeLimit(.minutes(1)))
    func editedTextWins() async throws {
        let db = try AppDatabase.makeInMemory()
        try await DocumentRepository(database: db).insert(TestData.document(id: "d1", title: "Doc"))
        var highlight = TestData.highlight(documentId: "d1", id: "h1", text: "Original", positionKey: 1)
        highlight.richText = "**Original**"
        highlight.editedText = "Edited *x*"
        try await HighlightRepository(database: db).insert(highlight)

        let content = try await ExportRepository(database: db).content(for: .document("d1"))
        #expect(content.documents.first?.highlights.first?.body == "Edited \\*x\\*")
        let output = Self.render(content)
        #expect(output.contains("  Edited \\*x\\*\n"))
        #expect(!output.contains("Original"))
    }

    @Test(.timeLimit(.minutes(1)))
    func documentsOrderedByTitle() {
        func document(_ id: String, _ title: String) -> ExportDocument {
            ExportDocument(
                id: id, title: title, author: "", categoryName: "Other", documentNote: nil,
                highlights: [Self.highlight("h-\(id)", color: .yellow, page: nil, body: "x", position: 1)]
            )
        }
        let output = Self.render(ExportContent(scopeName: "S", documents: [document("1", "b"), document("2", "A")]))
        let first = output.range(of: "## A\n")
        let second = output.range(of: "## b\n")
        #expect(first != nil && second != nil)
        if let first, let second { #expect(first.lowerBound < second.lowerBound) }
        #expect(output.contains("_Other_"))
        #expect(output.contains("2 highlights from 2 documents"))
    }

    @Test(.timeLimit(.minutes(1)))
    func noTrailingSpacesOrDoubleBlankLines() {
        var messy = Self.lectureContent()
        messy.documents[0].documentNote = "Para one   \n\n\n\nPara two\t"
        messy.documents[0].highlights[0].body = "Line   \n\n\n   \nnext line  "
        messy.documents[0].highlights[0].note = "a  \n \n\n\nb  "
        let contents = [Self.lectureContent(), messy, ExportContent(scopeName: "All highlights", documents: [])]
        let optionSets = [
            ExportOptions(),
            ExportOptions(groupBy: .tag),
            ExportOptions(includeNotes: false, includeDocumentNotes: false, includeImages: false),
            ExportOptions(includeNotes: false, includeDocumentNotes: false, includeImages: false, groupBy: .tag),
        ]
        for content in contents {
            for options in optionSets {
                let output = Self.render(content, options)
                #expect(output.hasSuffix("\n") && !output.hasSuffix("\n\n"))
                #expect(!output.contains("\n\n\n"))
                #expect(!output.contains(" \n") && !output.contains("\t\n"))
                #expect(!output.hasPrefix("\n"))
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func pageAndAuthorAreOptional() {
        let content = ExportContent(scopeName: "S", documents: [
            ExportDocument(
                id: "d1", title: "Doc", author: "", categoryName: "Paper", documentNote: nil,
                highlights: [Self.highlight("h1", color: .pink, page: nil, body: "No page", position: 1)]
            ),
        ])
        let byDocument = Self.render(content)
        #expect(byDocument.contains("- **Question**\n  No page\n"))
        #expect(byDocument.contains("_Paper_\n"))
        let byTag = Self.render(content, ExportOptions(groupBy: .tag))
        #expect(byTag.contains("  _— Doc_\n"))
        #expect(byTag.contains("## Untagged"))
    }

    @Test(.timeLimit(.minutes(1)))
    func blockConstructsInBodyAreNeutralised() {
        let body = "# Heading\n> Quote\n- item\n+ plus\n1. one\n2) two\n<b>x</b> | y ~~z~~"
        let content = ExportContent(scopeName: "S", documents: [
            ExportDocument(
                id: "d1", title: "Doc", author: "", categoryName: "Paper", documentNote: nil,
                highlights: [Self.highlight("h1", color: .yellow, page: 0, body: body, position: 1)]
            ),
        ])
        let output = Self.render(content)
        #expect(output.contains("""
              \\# Heading
              \\> Quote
              \\- item
              \\+ plus
              1\\. one
              2\\) two
              \\<b>x\\</b> \\| y \\~\\~z\\~\\~

            """))
    }

    @Test(.timeLimit(.minutes(1)))
    func multiLineCodeSpanStartsNoBlock() {
        let content = ExportContent(scopeName: "S", documents: [
            ExportDocument(
                id: "d1", title: "Doc", author: "", categoryName: "Paper", documentNote: nil,
                highlights: [Self.highlight("h1", color: .yellow, page: 0, body: "`` `a\n- b` ``", position: 1)]
            ),
        ])
        let lines = Self.render(content).components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(!lines.contains { $0.hasPrefix("- b") })
        #expect(lines.contains("`` `a - b` ``"))
        #expect(ExportMarkdownSafety.neutralise("`x\ny`") == "`x y`")
    }

    @Test(.timeLimit(.minutes(1)))
    func safetyRules() {
        func neutralise(_ text: String) -> String { ExportMarkdownSafety.neutralise(text) }
        #expect(neutralise("    indented\n\tTabbed") == "indented\nTabbed")
        #expect(neutralise("2024 was a year") == "2024 was a year")
        #expect(neutralise("1.5 is a number") == "1\\.5 is a number")
        #expect(neutralise("=== \n---") == "\\=== \n\\---")
        #expect(neutralise("`a < b | c ~ d`") == "`a < b | c ~ d`")
        #expect(neutralise("``x ` <y>`` and <z>") == "``x ` <y>`` and \\<z>")
        #expect(neutralise("stray ` tick <") == "stray ` tick \\<")
        #expect(neutralise("wow![link](http://x.y)") == "wow\\![link](http://x.y)")
        #expect(neutralise("!\\[x\\]") == "!\\[x\\]")
        #expect(neutralise("\\# kept \\< kept") == "\\# kept \\< kept")
        #expect(neutralise("R&D &amp; &#35; AT&T 5 & 6") == "R\\&D \\&amp; \\&#35; AT\\&T 5 & 6")
        #expect(neutralise("a\r\n# b") == "a\n\\# b")
        #expect(neutralise("**bold** and *it*") == "**bold** and *it*")
        #expect(neutralise("") == "")
    }
}
