import Foundation
import GRDB
import Testing
@testable import StudyReader

/// In-memory library plus the repositories the search tests write through. Shared with SearchIndexSyncTests.
struct SearchTestEnvironment: Sendable {
    let database: AppDatabase
    let documents: DocumentRepository
    let highlights: HighlightRepository
    let notes: NotesRepository
    let tags: TagRepository
    let texts: DocumentTextRepository
    let service: SearchService
    let now = FixedNow(TestData.referenceDate)

    init() throws {
        let database = try AppDatabase.makeInMemory()
        self.database = database
        self.documents = DocumentRepository(database: database)
        self.highlights = HighlightRepository(database: database)
        self.notes = NotesRepository(database: database)
        self.tags = TagRepository(database: database)
        self.texts = DocumentTextRepository(database: database)
        self.service = SearchService(database: database)
    }

    /// Inserts a document; `pages` become `documentText` units 0, 1, 2, ... (pages or sections).
    @discardableResult
    func addDocument(
        title: String = "Test Document",
        author: String = "",
        categoryId: String = BuiltinCategory.lectureSlides.id,
        fileType: FileType = .pdf,
        pages: [String] = []
    ) async throws -> LibraryDocument {
        let document = TestData.document(title: title, author: author, categoryId: categoryId, fileType: fileType)
        try await documents.insert(document)
        if !pages.isEmpty {
            try await setPages(pages, documentId: document.id)
        }
        return document
    }

    func setPages(_ pages: [String], documentId: String) async throws {
        var units: [DocumentText] = []
        var offset = 0
        for (index, text) in pages.enumerated() {
            units.append(DocumentText(documentId: documentId, unitIndex: index, startOffset: offset, text: text))
            offset += text.utf16.count
        }
        try await texts.replaceUnits(units, documentId: documentId, version: 1)
    }

    @discardableResult
    func addHighlight(
        documentId: String,
        text: String,
        note: String = "",
        pageIndex: Int? = nil,
        tagIds: [String] = []
    ) async throws -> Highlight {
        var highlight = TestData.highlight(documentId: documentId, text: text, note: note)
        highlight.pageIndex = pageIndex
        try await highlights.insert(highlight, tagIds: tagIds)
        return highlight
    }

    func tag(_ name: String) async throws -> LibraryTag {
        try await tags.findOrCreate(name: name, at: now())
    }

    /// Fails the test if any external-content index disagrees with its content table.
    func checkIntegrity() async throws {
        try await database.writer.write { db in
            try FTSIntegrity.check(db)
        }
    }
}

@Suite struct SearchServiceTests {
    @Test func findsDocumentText() async throws {
        let env = try SearchTestEnvironment()
        let document = try await env.addDocument(
            title: "Deep Learning",
            pages: ["Introduction to the course.", "Linear models.", "We derive backpropagation step by step."]
        )

        let results = try await env.service.search("backpropagation")

        #expect(results.documents.count == 1)
        let hit = try #require(results.documents.first)
        #expect(hit.documentId == document.id)
        #expect(hit.title == "Deep Learning")
        #expect(hit.field == .text)
        #expect(hit.unitIndex == 2)
        #expect(hit.snippet.contains("**backpropagation**"))
        #expect(results.highlights.isEmpty)
        #expect(results.notes.isEmpty)
        try await env.checkIntegrity()
    }

    @Test func findsTitlesAndAuthors() async throws {
        let env = try SearchTestEnvironment()
        let document = try await env.addDocument(title: "Neural Networks", author: "Ada Lovelace")

        let byTitle = try await env.service.search("neural")
        let byAuthor = try await env.service.search("lovelace")

        for results in [byTitle, byAuthor] {
            #expect(results.documents.count == 1)
            let hit = try #require(results.documents.first)
            #expect(hit.documentId == document.id)
            #expect(hit.field == .titleOrAuthor)
            #expect(hit.unitIndex == nil)
            #expect(hit.snippet.contains("**"))
        }
        #expect(try #require(byTitle.documents.first).snippet.contains("**Neural**"))
        #expect(try #require(byAuthor.documents.first).snippet.contains("**Lovelace**"))
        try await env.checkIntegrity()
    }

    @Test func findsHighlights() async throws {
        let env = try SearchTestEnvironment()
        let document = try await env.addDocument(title: "Optimization")
        let highlight = try await env.addHighlight(documentId: document.id, text: "gradient descent", pageIndex: 4)

        let results = try await env.service.search("gradient")

        #expect(results.highlights.count == 1)
        let hit = try #require(results.highlights.first)
        #expect(hit.highlightId == highlight.id)
        #expect(hit.documentId == document.id)
        #expect(hit.documentTitle == "Optimization")
        #expect(hit.pageIndex == 4)
        #expect(hit.snippet.contains("**gradient**"))
        #expect(results.documents.isEmpty)
        #expect(results.notes.isEmpty)
        try await env.checkIntegrity()
    }

    @Test func findsNotes() async throws {
        let env = try SearchTestEnvironment()
        let document = try await env.addDocument(title: "Calculus")
        let highlight = try await env.addHighlight(
            documentId: document.id, text: "derivative of a composition", note: "remember the chain rule"
        )
        try await env.notes.saveDocumentNote(documentId: document.id, body: "exam on Friday", at: env.now())

        let chain = try await env.service.search("chain")
        #expect(chain.notes.count == 1)
        let highlightNote = try #require(chain.notes.first)
        #expect(highlightNote.kind == .highlightNote)
        #expect(highlightNote.highlightId == highlight.id)
        #expect(highlightNote.documentId == document.id)
        #expect(highlightNote.documentTitle == "Calculus")
        #expect(highlightNote.snippet.contains("**chain**"))
        #expect(chain.highlights.isEmpty)

        let friday = try await env.service.search("friday")
        #expect(friday.notes.count == 1)
        let documentNote = try #require(friday.notes.first)
        #expect(documentNote.kind == .documentNote)
        #expect(documentNote.documentId == document.id)
        #expect(documentNote.highlightId == nil)
        #expect(documentNote.snippet.contains("**Friday**"))
        #expect(friday.highlights.isEmpty)

        // The highlight's own text is a highlight hit, not a note hit.
        let composition = try await env.service.search("composition")
        #expect(composition.highlights.map(\.highlightId) == [highlight.id])
        #expect(composition.notes.isEmpty)
        try await env.checkIntegrity()
    }

    @Test func phrasePrefixExclusion() async throws {
        let env = try SearchTestEnvironment()
        let phrase = try await env.addDocument(title: "A", pages: ["the chain rule is key", "network of nodes"])
        let scattered = try await env.addDocument(title: "B", pages: ["a rule for the chain", "backpropagation here"])
        let both = try await env.addDocument(title: "C", pages: ["a convolutional network"])

        let unquoted = try await env.service.search("chain rule")
        #expect(Set(unquoted.documents.map(\.documentId)) == [phrase.id, scattered.id])

        let quoted = try await env.service.search("\"chain rule\"")
        #expect(quoted.documents.map(\.documentId) == [phrase.id])

        let prefix = try await env.service.search("backprop*")
        #expect(prefix.documents.map(\.documentId) == [scattered.id])

        let network = try await env.service.search("network")
        #expect(Set(network.documents.map(\.documentId)) == [phrase.id, both.id])
        let excluded = try await env.service.search("network -convolutional")
        #expect(excluded.documents.map(\.documentId) == [phrase.id])
        try await env.checkIntegrity()
    }

    @Test func normalizedMatches() async throws {
        let env = try SearchTestEnvironment()
        let document = try await env.addDocument(
            title: "Biology",
            pages: [
                "The \(SearchSamples.photosynthesisSoftHyphen) process. We \(SearchSamples.findLigature) it. Caf\u{00E9} au lait."
            ]
        )

        for query in ["photosynthesis", "find", "cafe"] {
            let results = try await env.service.search(query)
            #expect(results.documents.map(\.documentId) == [document.id], "Query \(query)")
            #expect(results.documents.first?.snippet.contains("**") == true, "Query \(query)")
        }
        try await env.checkIntegrity()
    }

    @Test func filtersApply() async throws {
        let env = try SearchTestEnvironment()
        let t1 = try await env.tag("t1")
        let t2 = try await env.tag("t2")

        // d1: PDF, lecture slides, document tag t1; its highlight carries t2.
        let d1 = try await env.addDocument(
            title: "One", categoryId: BuiltinCategory.lectureSlides.id, fileType: .pdf, pages: ["kernel methods"]
        )
        try await env.tags.setTags([t1.id], forDocument: d1.id)
        let h1 = try await env.addHighlight(documentId: d1.id, text: "kernel highlight", tagIds: [t2.id])

        // d2: Markdown, paper, no document tag; its highlight carries t1.
        let d2 = try await env.addDocument(
            title: "Two", categoryId: BuiltinCategory.paper.id, fileType: .markdown, pages: ["kernel notes"]
        )
        let h2 = try await env.addHighlight(documentId: d2.id, text: "kernel idea", tagIds: [t1.id])
        try await env.notes.saveDocumentNote(documentId: d2.id, body: "kernel exam", at: env.now())

        func run(_ filters: SearchFilters) async throws -> (docs: Set<String>, highlights: Set<String>, notes: Int) {
            let results = try await env.service.search("kernel", filters: filters)
            return (
                Set(results.documents.map(\.documentId)),
                Set(results.highlights.map(\.highlightId)),
                results.notes.count
            )
        }

        let all = try await run(SearchFilters())
        #expect(all.docs == [d1.id, d2.id])
        #expect(all.highlights == [h1.id, h2.id])
        #expect(all.notes == 1)

        // Tag: document tag for document hits, highlight tag for highlight hits.
        let tagOne = try await run(SearchFilters(tagId: t1.id))
        #expect(tagOne.docs == [d1.id])
        #expect(tagOne.highlights == [h2.id])
        #expect(tagOne.notes == 0)

        let tagTwo = try await run(SearchFilters(tagId: t2.id))
        #expect(tagTwo.docs.isEmpty)
        #expect(tagTwo.highlights == [h1.id])

        let paper = try await run(SearchFilters(categoryId: BuiltinCategory.paper.id))
        #expect(paper.docs == [d2.id])
        #expect(paper.highlights == [h2.id])
        #expect(paper.notes == 1)

        let pdf = try await run(SearchFilters(fileType: .pdf))
        #expect(pdf.docs == [d1.id])
        #expect(pdf.highlights == [h1.id])
        #expect(pdf.notes == 0)

        let markdown = try await run(SearchFilters(fileType: .markdown))
        #expect(markdown.docs == [d2.id])
        #expect(markdown.notes == 1)

        // Combined filters intersect.
        let tagAndMarkdown = try await run(SearchFilters(tagId: t1.id, fileType: .markdown))
        #expect(tagAndMarkdown.docs.isEmpty)
        #expect(tagAndMarkdown.highlights == [h2.id])

        let tagAndPDF = try await run(SearchFilters(tagId: t1.id, fileType: .pdf))
        #expect(tagAndPDF.docs == [d1.id])
        #expect(tagAndPDF.highlights.isEmpty)

        let none = try await run(SearchFilters(tagId: t2.id, categoryId: BuiltinCategory.paper.id, fileType: .pdf))
        #expect(none.docs.isEmpty)
        #expect(none.highlights.isEmpty)
        #expect(none.notes == 0)
        try await env.checkIntegrity()
    }

    @Test func rankingOrdersByBm25() async throws {
        let env = try SearchTestEnvironment()
        let once = try await env.addDocument(title: "Once", pages: ["kernel filler filler filler filler filler"])
        let often = try await env.addDocument(title: "Often", pages: ["kernel kernel kernel kernel kernel filler"])

        let results = try await env.service.search("kernel")

        #expect(results.documents.map(\.documentId) == [often.id, once.id])
        #expect(results.documents[0].rank < results.documents[1].rank)
        try await env.checkIntegrity()
    }

    @Test func emptyOrNegativeOnlyQuery() async throws {
        let env = try SearchTestEnvironment()
        try await env.addDocument(title: "Something", pages: ["x marks the spot"])

        for query in ["", "   ", "-x", "-x -y"] {
            let results = try await env.service.search(query)
            #expect(results.isEmpty, "Query \(query)")
        }
        try await env.checkIntegrity()
    }

    @Test func malformedInputsDoNotThrow() async throws {
        let env = try SearchTestEnvironment()
        let document = try await env.addDocument(title: "Alpha", pages: ["alpha beta"])
        try await env.addHighlight(documentId: document.id, text: "alpha highlight", note: "alpha note")

        // NUL truncates the MATCH argument, and punctuation-only terms normalize to no tokens (BACKLOG B20).
        let inputs = [
            "alpha\u{0}beta", "\u{0}", "+", "+ -x", "(*", "(", ".", "\"+\"", "\"", "a\u{0}",
            "title:x", "^a", "NOT AND NEAR", "\u{2028}", "\u{0085}alpha",
        ]
        for input in inputs {
            do {
                _ = try await env.service.search(input)
            } catch {
                Issue.record("Query \(input.debugDescription) threw \(error)")
            }
        }
        try await env.checkIntegrity()
    }

    @Test func limitAppliesPerGroup() async throws {
        let env = try SearchTestEnvironment()
        for index in 0..<3 {
            let document = try await env.addDocument(title: "Doc \(index)", pages: ["shared word \(index)"])
            try await env.addHighlight(documentId: document.id, text: "shared highlight \(index)")
        }

        let limited = try await env.service.search("shared", limit: 2)
        #expect(limited.documents.count == 2)
        #expect(limited.highlights.count == 2)

        let unlimited = try await env.service.search("shared")
        #expect(unlimited.documents.count == 3)
        #expect(unlimited.highlights.count == 3)

        let zero = try await env.service.search("shared", limit: 0)
        #expect(zero.isEmpty)
        try await env.checkIntegrity()
    }
}
