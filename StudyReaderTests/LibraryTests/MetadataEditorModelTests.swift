import Foundation
import Testing
@testable import StudyReader

@Suite("MetadataEditorModel") @MainActor
struct MetadataEditorModelTests {
    private static let documentId = "50000000-0000-0000-0000-0000000000E1"
    private static let markdownId = "50000000-0000-0000-0000-0000000000E2"

    private func makeEnvironment() throws -> AppEnvironment {
        try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
    }

    @Test(.timeLimit(.minutes(1)))
    func loadAndSave() async throws {
        let env = try makeEnvironment()
        defer { TestFileStore.remove(env.fileStore) }
        let session = AppSession(environment: env)
        try await env.documentRepository.insert(
            TestData.document(id: Self.documentId, title: "Old title", author: "Old author")
        )
        let lab = try await env.categoryRepository.create(name: "Lab")
        let model = MetadataEditorModel(documentId: Self.documentId, currentPageIndex: nil, session: session)

        await model.load()
        #expect(model.errorMessage == nil)
        #expect(model.title == "Old title")
        #expect(model.author == "Old author")
        #expect(model.categoryId == BuiltinCategory.lectureSlides.id)
        #expect(model.categories.contains { $0.id == lab.id })
        #expect(model.selectedCategoryName == "Lecture slides")

        model.title = "New title"
        model.author = "New author"
        model.categoryId = lab.id
        #expect(await model.save())
        #expect(model.errorMessage == nil)

        let row = try #require(try await env.documentRepository.fetch(id: Self.documentId))
        #expect(row.title == "New title")
        #expect(row.author == "New author")
        #expect(row.categoryId == lab.id)
    }

    @Test(.timeLimit(.minutes(1)))
    func emptyTitleShowsError() async throws {
        let env = try makeEnvironment()
        defer { TestFileStore.remove(env.fileStore) }
        let session = AppSession(environment: env)
        try await env.documentRepository.insert(TestData.document(id: Self.documentId, title: "Keep me"))
        let model = MetadataEditorModel(documentId: Self.documentId, currentPageIndex: nil, session: session)
        await model.load()

        model.title = "   "
        #expect(await model.save() == false)
        #expect(model.titleError == "A title is required.")
        #expect(model.errorMessage == nil)

        let row = try #require(try await env.documentRepository.fetch(id: Self.documentId))
        #expect(row.title == "Keep me")

        // Changing the title clears the field's message; a corrected title saves.
        model.title = "Fixed"
        #expect(model.titleError == nil)
        #expect(await model.save())
        #expect(model.titleError == nil)
        #expect(model.errorMessage == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func hasLoadedAfterLoadEvenWhenTheDocumentIsMissing() async throws {
        let env = try makeEnvironment()
        defer { TestFileStore.remove(env.fileStore) }
        let session = AppSession(environment: env)
        try await env.documentRepository.insert(TestData.document(id: Self.documentId))

        let model = MetadataEditorModel(documentId: Self.documentId, currentPageIndex: nil, session: session)
        #expect(model.hasLoaded == false)
        await model.load()
        #expect(model.hasLoaded)
        #expect(model.errorMessage == nil)

        // A missing document still counts as loaded, with the error shown.
        let missing = MetadataEditorModel(documentId: Self.markdownId, currentPageIndex: nil, session: session)
        await missing.load()
        #expect(missing.hasLoaded)
        #expect(missing.errorMessage != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func coverActions() async throws {
        let env = try makeEnvironment()
        defer { TestFileStore.remove(env.fileStore) }
        let session = AppSession(environment: env)
        let store = env.fileStore

        try store.createDocumentFolder(documentId: Self.documentId)
        let original = try store.originalFileURL(documentId: Self.documentId, fileType: .pdf)
        try PDFFixtureBuilder.coloredRegion().write(to: original)
        try await env.documentRepository.insert(TestData.document(id: Self.documentId, fileType: .pdf))

        let model = MetadataEditorModel(documentId: Self.documentId, currentPageIndex: 0, session: session)
        await model.load()
        #expect(model.canUseCurrentPage)

        let startVersion = model.coverVersion
        await model.useCurrentPageAsCover()
        #expect(model.errorMessage == nil)
        #expect(model.coverVersion == startVersion + 1)
        #expect(model.document?.coverSource == .page)

        await model.resetCover()
        #expect(model.errorMessage == nil)
        #expect(model.coverVersion == startVersion + 2)
        #expect(model.document?.coverSource == .automatic)
        let row = try #require(try await env.documentRepository.fetch(id: Self.documentId))
        #expect(row.coverSource == .automatic)
    }

    @Test(.timeLimit(.minutes(1)))
    func categoryPickerWaitsForValidSelection() async throws {
        let env = try makeEnvironment()
        defer { TestFileStore.remove(env.fileStore) }
        let session = AppSession(environment: env)
        try await env.documentRepository.insert(
            TestData.document(id: Self.documentId, title: "Old title", author: "Old author")
        )

        let model = MetadataEditorModel(documentId: Self.documentId, currentPageIndex: nil, session: session)
        // Before load() the selection is "" and there are no categories, so the picker must not be shown.
        #expect(model.hasValidCategorySelection == false)

        await model.load()
        #expect(model.hasValidCategorySelection)

        model.categoryId = "missing"
        #expect(model.hasValidCategorySelection == false)

        // A document that doesn't exist: the load fails and no category is selected.
        let missing = MetadataEditorModel(documentId: Self.markdownId, currentPageIndex: nil, session: session)
        await missing.load()
        #expect(missing.errorMessage != nil)
        #expect(missing.hasValidCategorySelection == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func currentPageRequiresPDFAndAPage() async throws {
        let env = try makeEnvironment()
        defer { TestFileStore.remove(env.fileStore) }
        let session = AppSession(environment: env)
        try await env.documentRepository.insert(TestData.document(id: Self.documentId, fileType: .pdf))
        try await env.documentRepository.insert(TestData.document(id: Self.markdownId, fileType: .markdown))

        // Library sheets have no page, so the action stays hidden even for a PDF.
        let noPage = MetadataEditorModel(documentId: Self.documentId, currentPageIndex: nil, session: session)
        await noPage.load()
        #expect(noPage.canUseCurrentPage == false)

        // Markdown never has pages, even when a page index is passed.
        let markdown = MetadataEditorModel(documentId: Self.markdownId, currentPageIndex: 0, session: session)
        await markdown.load()
        #expect(markdown.canUseCurrentPage == false)
    }
}
