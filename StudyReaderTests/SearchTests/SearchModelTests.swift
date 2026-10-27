import Foundation
import Testing
@testable import StudyReader

@MainActor
struct SearchModelTests {
    private func seed(_ session: AppSession) async throws -> (gradient: LibraryDocument, graph: LibraryDocument) {
        let environment = session.environment
        let gradient = TestData.document(title: "Optimization", categoryId: BuiltinCategory.lectureSlides.id)
        let graph = TestData.document(title: "Networks", categoryId: BuiltinCategory.paper.id)
        try await environment.documentRepository.insert(gradient)
        try await environment.documentRepository.insert(graph)
        try await environment.documentTextRepository.replaceUnits(
            [DocumentText(documentId: gradient.id, unitIndex: 0, startOffset: 0, text: "The gradient points uphill.")],
            documentId: gradient.id, version: 1
        )
        try await environment.documentTextRepository.replaceUnits(
            [DocumentText(documentId: graph.id, unitIndex: 0, startOffset: 0, text: "A graph has edges and a gradient too.")],
            documentId: graph.id, version: 1
        )
        return (gradient, graph)
    }

    @Test func debouncedSearch() async throws {
        let sleeper = ManualSleeper()
        let session = try ReaderTestSupport.makeSession(sleeper: sleeper)
        defer { ReaderTestSupport.cleanUp(session) }
        let docs = try await seed(session)
        let search = session.search

        search.query = "gra"
        search.query = "grad"
        search.query = "gradient"
        await sleeper.waitForSleepers(3)
        #expect(search.results.isEmpty, "Nothing runs before the debounce delay passes.")
        await sleeper.resumeAll()

        let found = await ReaderTestSupport.waitUntil { !search.results.documents.isEmpty }
        #expect(found)
        #expect(Set(search.results.documents.map(\.documentId)) == [docs.gradient.id, docs.graph.id])
        #expect(search.results.documents.allSatisfy { $0.fileType == .pdf })
    }

    @Test func filtersTriggerSearch() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        let docs = try await seed(session)
        let search = session.search

        search.query = "gradient"
        let both = await ReaderTestSupport.waitUntil { search.results.documents.count == 2 }
        #expect(both)

        search.filters.categoryId = BuiltinCategory.paper.id
        let narrowed = await ReaderTestSupport.waitUntil { search.results.documents.count == 1 }
        #expect(narrowed)
        #expect(search.results.documents.first?.documentId == docs.graph.id)

        search.clear()
        #expect(search.query.isEmpty)
        #expect(search.filters == SearchFilters())
        #expect(search.results.isEmpty)
        #expect(!search.isActive)
    }

    @Test func locations() {
        let text = DocumentHit(documentId: "d", title: "T", field: .text, unitIndex: 3, snippet: "s", rank: 0)
        #expect(SearchModel.location(for: text, query: "q") == .searchHit(unitIndex: 3, query: "q"))
        let title = DocumentHit(documentId: "d", title: "T", field: .titleOrAuthor, unitIndex: nil, snippet: "s", rank: 0)
        #expect(SearchModel.location(for: title, query: "q") == nil)

        let highlight = HighlightHit(highlightId: "h", documentId: "d", documentTitle: "T", pageIndex: 1, snippet: "s", rank: 0)
        #expect(SearchModel.location(for: highlight) == .highlight("h"))

        let highlightNote = NoteHit(kind: .highlightNote, documentId: "d", documentTitle: "T", highlightId: "h", snippet: "s", rank: 0)
        #expect(SearchModel.location(for: highlightNote) == .highlight("h"))
        let documentNote = NoteHit(kind: .documentNote, documentId: "d", documentTitle: "T", highlightId: nil, snippet: "s", rank: 0)
        #expect(SearchModel.location(for: documentNote) == .documentNote)
    }

    @Test func snippetBolding() {
        let snippet = attributedSnippet("a **b** c **d**")
        #expect(String(snippet.characters) == "a b c d")
        for run in snippet.runs {
            let text = String(snippet[run.range].characters)
            let bold = run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
            #expect(bold == (text == "b" || text == "d"), "Run \"\(text)\" has the wrong emphasis.")
        }
    }
}
