import AppKit
import Foundation
import GRDB
import Testing
@testable import StudyReader

@MainActor
@Suite("HighlightsBrowserModel")
struct HighlightsBrowserModelTests {
    private static let docA = "10000000-0000-0000-0000-0000000000A1"
    private static let docB = "10000000-0000-0000-0000-0000000000B2"
    private static let tagA = "30000000-0000-0000-0000-0000000000D1"
    private static let tagB = "30000000-0000-0000-0000-0000000000D2"
    private static let h1 = "20000000-0000-0000-0000-0000000000E1"
    private static let h2 = "20000000-0000-0000-0000-0000000000E2"
    private static let h3 = "20000000-0000-0000-0000-0000000000E3"
    private static let h4 = "20000000-0000-0000-0000-0000000000E4"
    private static let h5 = "20000000-0000-0000-0000-0000000000E5"
    private static let h6 = "20000000-0000-0000-0000-0000000000E6"
    private static let day: TimeInterval = 86_400

    /// Same fixture as `HighlightBrowseQueryTests`: two documents, two tags, six highlights.
    private static func makeModel() async throws -> (HighlightsBrowserModel, AppEnvironment) {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        let t0 = TestData.referenceDate
        let db = env.database
        try await DocumentRepository(database: db).insert(
            TestData.document(id: docA, title: "alpha lectures", categoryId: BuiltinCategory.lectureSlides.id)
        )
        try await DocumentRepository(database: db).insert(
            TestData.document(id: docB, title: "Beta paper", categoryId: BuiltinCategory.paper.id)
        )
        let banana = TestData.tag(name: "Banana", id: tagA)
        let apple = TestData.tag(name: "apple", id: tagB)
        try await db.writer.write { db in
            try banana.insert(db)
            try apple.insert(db)
        }
        var r1 = TestData.highlight(documentId: docA, id: h1, note: "", color: .yellow, positionKey: 10, createdAt: t0)
        r1.view = .pdf
        var r2 = TestData.highlight(documentId: docA, id: h2, note: "remember", color: .green, positionKey: 20, createdAt: t0.addingTimeInterval(day))
        r2.view = .markdown
        var r3 = TestData.highlight(documentId: docB, id: h3, note: "", color: .blue, positionKey: 5, createdAt: t0.addingTimeInterval(2 * day))
        r3.view = .pdf
        var r4 = TestData.highlight(documentId: docB, id: h4, note: "   ", color: .pink, positionKey: 15, createdAt: t0.addingTimeInterval(2 * day + 3600))
        r4.view = .markdown
        var r5 = TestData.highlight(documentId: docA, id: h5, note: "x", color: .purple, positionKey: 30, createdAt: t0.addingTimeInterval(7200))
        r5.view = .pdf
        var r6 = TestData.highlight(documentId: docB, id: h6, note: "", color: .yellow, positionKey: 1, createdAt: t0.addingTimeInterval(day + 5 * 3600))
        r6.view = .markdown
        let repo = env.highlightRepository
        try await repo.insert(r1, tagIds: [tagA, tagB])
        try await repo.insert(r2, tagIds: [tagA])
        try await repo.insert(r3, tagIds: [tagB])
        try await repo.insert(r4)
        try await repo.insert(r5)
        try await repo.insert(r6)
        return (HighlightsBrowserModel(environment: env), env)
    }

    private func ids(_ model: HighlightsBrowserModel) -> [String] {
        model.items.map { $0.highlight.id }
    }

    /// Runs `observe()` for the model's current query until the list equals `expected` (or a bounded wait ends).
    private func observed(_ model: HighlightsBrowserModel, expecting expected: [String]) async -> [String] {
        let task = Task { await model.observe() }
        defer { task.cancel() }
        for _ in 0..<200 {
            if model.hasLoaded, ids(model) == expected { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return ids(model)
    }

    @Test(.timeLimit(.minutes(1)))
    func exportSelectionIgnoresASecondCall() async throws {
        let base = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        let gated = GatedHTTPClient([
            .response(status: 200, body: #"{"importFormats":{"text/markdown":["application/vnd.google-apps.document"]}}"#),
            .response(status: 200, body: #"{"id": "FILE1"}"#)
        ])
        let env = AppEnvironment(
            fileStore: base.fileStore,
            database: base.database,
            now: base.now,
            settingsStore: TestSettings.make(),
            httpClient: gated,
            googleAuth: StubGoogleAuth()
        )
        try await env.documentRepository.insert(TestData.document(id: Self.docA, title: "alpha"))
        try await env.highlightRepository.insert(TestData.highlight(documentId: Self.docA, id: Self.h1))
        let model = HighlightsBrowserModel(environment: env)
        model.selection = [Self.h1]

        let first = Task { await model.exportSelection() }
        var polls = 0
        while await gated.requestCount < 1, polls < 400 {
            polls += 1
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(model.isExporting)

        await model.exportSelection()
        #expect(await gated.requestCount == 1)
        #expect(model.isExporting)

        await gated.open()
        await first.value
        #expect(model.isExporting == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func thumbnailsArePrunedWithTheList() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        try await env.documentRepository.insert(TestData.document(id: Self.docA, title: "alpha"))
        let url = try env.fileStore.snapshotURL(documentId: Self.docA, highlightId: Self.h1)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: url)

        let path = "\(Self.docA)/snapshots/\(Self.h1).png"
        var highlight = TestData.highlight(documentId: Self.docA, id: Self.h1)
        highlight.imagePath = path
        try await env.highlightRepository.insert(highlight)

        let model = HighlightsBrowserModel(environment: env)
        let task = Task { await model.observe() }
        defer { task.cancel() }
        for _ in 0..<200 where model.thumbnails[path] == nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(model.thumbnails[path] != nil)

        _ = try await env.highlightRepository.delete(id: Self.h1, fileStore: env.fileStore)
        for _ in 0..<200 where model.thumbnails[path] != nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(model.thumbnails[path] == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func listsEverythingNewestFirst() async throws {
        let (model, _) = try await Self.makeModel()
        let result = await observed(model, expecting: [Self.h4, Self.h3, Self.h6, Self.h2, Self.h5, Self.h1])
        #expect(result == [Self.h4, Self.h3, Self.h6, Self.h2, Self.h5, Self.h1])
    }

    @Test(.timeLimit(.minutes(1)))
    func filterCategoryAndColor() async throws {
        let (model, _) = try await Self.makeModel()
        model.toggle(categoryId: BuiltinCategory.paper.id)
        #expect(model.isFiltered)
        #expect(await observed(model, expecting: [Self.h4, Self.h3, Self.h6]) == [Self.h4, Self.h3, Self.h6])
        model.toggle(color: .yellow)
        #expect(await observed(model, expecting: [Self.h6]) == [Self.h6])
        model.clearFilters()
        #expect(!model.isFiltered)
    }

    @Test(.timeLimit(.minutes(1)))
    func filterTagAll() async throws {
        let (model, _) = try await Self.makeModel()
        model.toggle(tagId: Self.tagA)
        model.toggle(tagId: Self.tagB)
        model.filter.tagMode = .all
        #expect(await observed(model, expecting: [Self.h1]) == [Self.h1])
    }

    @Test(.timeLimit(.minutes(1)))
    func filterHasNote() async throws {
        let (model, _) = try await Self.makeModel()
        model.filter.hasNote = true
        #expect(await observed(model, expecting: [Self.h2, Self.h5]) == [Self.h2, Self.h5])
    }

    @Test(.timeLimit(.minutes(1)))
    func filterDateRange() async throws {
        let (model, _) = try await Self.makeModel()
        let t0 = TestData.referenceDate
        model.filter.createdFrom = t0.addingTimeInterval(2 * Self.day)
        model.filter.createdBefore = t0.addingTimeInterval(3 * Self.day)
        #expect(await observed(model, expecting: [Self.h4, Self.h3]) == [Self.h4, Self.h3])
    }

    @Test
    func dayHelpersUseInclusiveEnd() throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let model = HighlightsBrowserModel(environment: env, calendar: calendar)
        let day = TestData.referenceDate
        model.fromDay = day
        model.toDay = day
        let start = calendar.startOfDay(for: day)
        #expect(model.filter.createdFrom == start)
        #expect(model.filter.createdBefore == start.addingTimeInterval(Self.day))
        #expect(model.toDay == start)
    }

    @Test(.timeLimit(.minutes(1)))
    func sortDocumentPosition() async throws {
        let (model, _) = try await Self.makeModel()
        model.sort = .documentPosition
        let expected = [Self.h1, Self.h2, Self.h5, Self.h6, Self.h3, Self.h4]
        #expect(await observed(model, expecting: expected) == expected)
    }

    @Test(.timeLimit(.minutes(1)))
    func sortColor() async throws {
        let (model, _) = try await Self.makeModel()
        model.sort = .color
        let expected = [Self.h6, Self.h1, Self.h2, Self.h3, Self.h4, Self.h5]
        #expect(await observed(model, expecting: expected) == expected)
    }

    @Test(.timeLimit(.minutes(1)))
    func filtersCombine() async throws {
        let (model, _) = try await Self.makeModel()
        model.toggle(categoryId: BuiltinCategory.paper.id)
        model.toggle(color: .yellow)
        model.toggle(color: .pink)
        model.filter.hasNote = false
        #expect(await observed(model, expecting: [Self.h4, Self.h6]) == [Self.h4, Self.h6])
    }

    @Test(.timeLimit(.minutes(1)))
    func detailItemOnlyForSingleSelection() async throws {
        let (model, _) = try await Self.makeModel()
        _ = await observed(model, expecting: [Self.h4, Self.h3, Self.h6, Self.h2, Self.h5, Self.h1])
        #expect(model.detailItem == nil)
        model.selection = [Self.h2]
        #expect(model.detailItem?.id == Self.h2)
        model.selection = [Self.h2, Self.h3]
        #expect(model.detailItem == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func bulkActions() async throws {
        let (model, env) = try await Self.makeModel()
        let task = Task { await model.observe() }
        defer { task.cancel() }
        for _ in 0..<200 where model.items.count < 6 {
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(model.items.count == 6)

        model.selection = [Self.h1, Self.h2, Self.h3]
        await model.addTag(named: "exam")
        let tag = try #require(try await env.tagRepository.findOrCreate(name: "exam", at: TestData.referenceDate))
        for _ in 0..<200 where !model.items.filter({ model.selection.contains($0.id) }).allSatisfy({ $0.tagIds.contains(tag.id) }) {
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(model.selectedItems.allSatisfy { $0.tagIds.contains(tag.id) })

        await model.removeTag(tag.id)
        for _ in 0..<200 where model.selectedItems.contains(where: { $0.tagIds.contains(tag.id) }) {
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(model.selectedItems.allSatisfy { !$0.tagIds.contains(tag.id) })

        await model.setColor(.green)
        for _ in 0..<200 where !model.selectedItems.allSatisfy({ $0.highlight.color == .green }) {
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(model.selectedItems.allSatisfy { $0.highlight.color == .green })

        await model.deleteSelected()
        for _ in 0..<200 where model.items.count > 3 {
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(model.items.count == 3)
        #expect(model.selection.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test
    func countTextAgreesWithCount() {
        #expect(HighlightsBrowserModel.countText(0) == "0 highlights")
        #expect(HighlightsBrowserModel.countText(1) == "1 highlight")
        #expect(HighlightsBrowserModel.countText(2) == "2 highlights")
    }

    @Test
    func deleteTitleAgreesWithCount() {
        #expect(HighlightsBrowserModel.deleteTitle(count: 1) == "Delete 1 highlight?")
        #expect(HighlightsBrowserModel.deleteTitle(count: 2) == "Delete 2 highlights?")
    }
}
