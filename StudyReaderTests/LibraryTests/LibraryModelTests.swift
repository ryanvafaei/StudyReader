import Foundation
import Testing
@testable import StudyReader

@Suite("LibraryModel") @MainActor
struct LibraryModelTests {
    private static let day: TimeInterval = 86_400

    private func item(
        _ title: String,
        id: String = UUID().uuidString,
        author: String = "",
        addedAt: Date = TestData.referenceDate,
        lastOpenedAt: Date? = nil,
        categoryId: String = BuiltinCategory.lectureSlides.id,
        fileType: FileType = .pdf,
        highlightCount: Int = 0,
        tagIds: [String] = []
    ) -> LibraryItem {
        var document = TestData.document(
            id: id,
            title: title,
            author: author,
            categoryId: categoryId,
            fileType: fileType,
            addedAt: addedAt
        )
        document.lastOpenedAt = lastOpenedAt
        return LibraryItem(
            document: document,
            categoryName: "",
            highlightCount: highlightCount,
            tagIds: tagIds
        )
    }

    private func titles(_ items: [LibraryItem]) -> [String] {
        items.map(\.document.title)
    }

    // MARK: - Sort

    @Test func sortDateAdded() {
        let ref = TestData.referenceDate
        let items = [
            item("Old", addedAt: ref.addingTimeInterval(-Self.day)),
            item("New", addedAt: ref.addingTimeInterval(Self.day)),
            item("Middle", addedAt: ref),
        ]

        let sorted = LibraryModel.sorted(items, by: .dateAdded)

        #expect(titles(sorted) == ["New", "Middle", "Old"])
    }

    @Test func sortLastOpened() {
        let ref = TestData.referenceDate
        let items = [
            item("Never old", addedAt: ref.addingTimeInterval(-10)),
            item("Opened old", addedAt: ref.addingTimeInterval(-300), lastOpenedAt: ref.addingTimeInterval(-50)),
            item("Never new", addedAt: ref.addingTimeInterval(10)),
            item("Opened new", addedAt: ref.addingTimeInterval(-200), lastOpenedAt: ref.addingTimeInterval(50)),
        ]

        let sorted = LibraryModel.sorted(items, by: .lastOpened)

        #expect(titles(sorted) == ["Opened new", "Opened old", "Never new", "Never old"])
    }

    @Test func sortTitle() {
        let items = [
            item("Lecture 10"),
            item("Lecture 2"),
            item("Alpha"),
        ]

        let sorted = LibraryModel.sorted(items, by: .title)

        #expect(titles(sorted) == ["Alpha", "Lecture 2", "Lecture 10"])
    }

    @Test func sortAuthor() {
        let items = [
            item("Untitled notes", author: ""),
            item("Zed topics", author: "Zimmer"),
            item("Beta", author: "Adams"),
            item("Alpha", author: "Adams"),
            item("Brown book", author: "Brown"),
        ]

        let sorted = LibraryModel.sorted(items, by: .author)

        #expect(titles(sorted) == ["Alpha", "Beta", "Brown book", "Zed topics", "Untitled notes"])
    }

    // MARK: - Filter

    @Test func filterCategory() {
        let items = [
            item("Paper", categoryId: BuiltinCategory.paper.id),
            item("Slides", categoryId: BuiltinCategory.lectureSlides.id),
        ]

        let filtered = LibraryModel.filtered(items, by: LibraryFilter(categoryId: BuiltinCategory.paper.id))

        #expect(titles(filtered) == ["Paper"])
    }

    @Test func filterTag() {
        let items = [
            item("Tagged", tagIds: ["tag-1", "tag-2"]),
            item("Other", tagIds: ["tag-2"]),
        ]

        let filtered = LibraryModel.filtered(items, by: LibraryFilter(tagId: "tag-1"))

        #expect(titles(filtered) == ["Tagged"])
    }

    @Test func filterFileType() {
        let items = [
            item("Notes", fileType: .markdown),
            item("Book", fileType: .pdf),
        ]

        let filtered = LibraryModel.filtered(items, by: LibraryFilter(fileType: .markdown))

        #expect(titles(filtered) == ["Notes"])
    }

    @Test func filterHasHighlights() {
        let items = [
            item("Highlighted", highlightCount: 2),
            item("Plain", highlightCount: 0),
        ]

        let filtered = LibraryModel.filtered(items, by: LibraryFilter(hasHighlightsOnly: true))

        #expect(titles(filtered) == ["Highlighted"])
    }

    @Test func filtersCombine() {
        let items = [
            item("Match", categoryId: BuiltinCategory.paper.id, fileType: .pdf, highlightCount: 1),
            item("Wrong category", categoryId: BuiltinCategory.notes.id, fileType: .pdf, highlightCount: 1),
            item("Wrong type", categoryId: BuiltinCategory.paper.id, fileType: .markdown, highlightCount: 1),
            item("No highlights", categoryId: BuiltinCategory.paper.id, fileType: .pdf, highlightCount: 0),
        ]
        let filter = LibraryFilter(
            categoryId: BuiltinCategory.paper.id,
            fileType: .pdf,
            hasHighlightsOnly: true
        )

        let filtered = LibraryModel.filtered(items, by: filter)

        #expect(titles(filtered) == ["Match"])
        #expect(filter.isActive)
        #expect(!LibraryFilter().isActive)
    }

    // MARK: - Model

    @Test(.timeLimit(.minutes(1)))
    func listsPersistedDocuments() async throws {
        let fileStore = TestFileStore.make()
        let settings = TestSettings.make()
        defer {
            TestFileStore.remove(fileStore)
            TestSettings.remove(settings)
        }
        let first = try AppEnvironment.make(fileStore: fileStore, settingsStore: settings)
        let read = TestData.document(id: "10000000-0000-0000-0000-0000000000a1", title: "Read me", author: "Ada")
        let other = TestData.document(id: "10000000-0000-0000-0000-0000000000a2", title: "Other")
        try await first.documentRepository.insert(read)
        try await first.documentRepository.insert(other)
        try await first.documentRepository.updateTextPosition(id: read.id, offset: 40, progress: 0.5)
        try await first.documentRepository.markOpened(id: read.id, at: TestData.referenceDate)
        try await first.highlightRepository.insert(TestData.highlight(documentId: read.id))

        // Second environment over the same folder: the library survives a restart.
        let second = try AppEnvironment.make(fileStore: fileStore, settingsStore: settings)
        let model = LibraryModel(environment: second)
        let task = Task { await model.observe() }
        try await waitUntil { model.items.count == 2 }
        task.cancel()
        await task.value

        let listed = try #require(model.items.first { $0.document.id == read.id })
        #expect(listed.document.title == "Read me")
        #expect(listed.document.author == "Ada")
        #expect(listed.categoryName == BuiltinCategory.lectureSlides.name)
        #expect(listed.highlightCount == 1)
        #expect(listed.document.progress == 0.5)
        #expect(listed.document.lastOpenedAt == TestData.referenceDate)
    }

    @Test func sortAndLayoutPersist() throws {
        let settings = TestSettings.make()
        defer { TestSettings.remove(settings) }
        let fileStore = TestFileStore.make()
        defer { TestFileStore.remove(fileStore) }
        let database = try AppDatabase.makeInMemory()
        let environment = AppEnvironment(
            fileStore: fileStore,
            database: database,
            now: FixedNow(TestData.referenceDate),
            settingsStore: settings
        )
        let model = LibraryModel(environment: environment)
        model.sort = .title
        model.layout = .list

        let reopened = LibraryModel(environment: environment)

        #expect(reopened.sort == .title)
        #expect(reopened.layout == .list)
        #expect(settings.librarySort == .title)
        #expect(settings.libraryLayout == .list)
    }

    @Test(.timeLimit(.minutes(1)))
    func deleteRemovesItem() async throws {
        let fileStore = TestFileStore.make()
        let settings = TestSettings.make()
        defer {
            TestFileStore.remove(fileStore)
            TestSettings.remove(settings)
        }
        let environment = try AppEnvironment.make(fileStore: fileStore, settingsStore: settings)
        // FileStore accepts only canonical (uppercase) UUID strings.
        let document = TestData.document(id: "10000000-0000-0000-0000-0000000000B1", title: "Doomed")
        try await environment.documentRepository.insert(document)
        _ = try fileStore.createDocumentFolder(documentId: document.id)
        let model = LibraryModel(environment: environment)
        let task = Task { await model.observe() }
        try await waitUntil { model.items.count == 1 }

        await model.delete(documentId: document.id)
        try await waitUntil { model.items.isEmpty }
        task.cancel()
        await task.value

        #expect(model.items.isEmpty)
        #expect(model.errorMessage == nil)
        let folder = try fileStore.documentFolderURL(documentId: document.id)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    /// Polls the observed model until `condition` holds, for at most about ten seconds.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<2_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
