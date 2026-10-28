import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("HighlightBrowseQuery")
struct HighlightBrowseQueryTests {
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

    /// Two documents (Lecture slides, Paper), two tags, six highlights spread over three days.
    /// h1: docA yellow pdf, note "", tags A+B. h2: docA green markdown, note "remember", tag A.
    /// h3: docB blue pdf, note "", tag B. h4: docB pink markdown, note "   " (blank). h5: docA purple pdf, note "x".
    /// h6: docB yellow markdown, note "".
    private static func seed(_ db: AppDatabase) async throws -> HighlightRepository {
        let t0 = TestData.referenceDate
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

        var h1Row = TestData.highlight(documentId: docA, id: h1, note: "", color: .yellow, positionKey: 10, createdAt: t0)
        h1Row.view = .pdf
        var h2Row = TestData.highlight(documentId: docA, id: h2, note: "remember", color: .green, positionKey: 20, createdAt: t0.addingTimeInterval(day))
        h2Row.view = .markdown
        var h3Row = TestData.highlight(documentId: docB, id: h3, note: "", color: .blue, positionKey: 5, createdAt: t0.addingTimeInterval(2 * day))
        h3Row.view = .pdf
        var h4Row = TestData.highlight(documentId: docB, id: h4, note: "   ", color: .pink, positionKey: 15, createdAt: t0.addingTimeInterval(2 * day + 3600))
        h4Row.view = .markdown
        var h5Row = TestData.highlight(documentId: docA, id: h5, note: "x", color: .purple, positionKey: 30, createdAt: t0.addingTimeInterval(7200))
        h5Row.view = .pdf
        var h6Row = TestData.highlight(documentId: docB, id: h6, note: "", color: .yellow, positionKey: 1, createdAt: t0.addingTimeInterval(day + 5 * 3600))
        h6Row.view = .markdown

        let repo = HighlightRepository(database: db)
        try await repo.insert(h1Row, tagIds: [tagA, tagB])
        try await repo.insert(h2Row, tagIds: [tagA])
        try await repo.insert(h3Row, tagIds: [tagB])
        try await repo.insert(h4Row)
        try await repo.insert(h5Row)
        try await repo.insert(h6Row)
        return repo
    }

    private static func ids(_ items: [HighlightListItem]) -> [String] {
        items.map { $0.highlight.id }
    }

    @Test(.timeLimit(.minutes(1)))
    func filterDocument() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = try await Self.seed(db)
        let filter = HighlightBrowserFilter(documentIds: [Self.docA])
        let items = try await repo.browse(filter: filter, sort: .createdNewest)
        #expect(Self.ids(items) == [Self.h2, Self.h5, Self.h1])
    }

    @Test(.timeLimit(.minutes(1)))
    func filterCategory() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = try await Self.seed(db)
        let filter = HighlightBrowserFilter(categoryIds: [BuiltinCategory.paper.id])
        let items = try await repo.browse(filter: filter, sort: .createdNewest)
        #expect(Self.ids(items) == [Self.h4, Self.h3, Self.h6])
    }

    @Test(.timeLimit(.minutes(1)))
    func filterTagAny() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = try await Self.seed(db)
        let filter = HighlightBrowserFilter(tagIds: [Self.tagA, Self.tagB], tagMode: .any)
        let items = try await repo.browse(filter: filter, sort: .createdNewest)
        #expect(Self.ids(items) == [Self.h3, Self.h2, Self.h1])
    }

    @Test(.timeLimit(.minutes(1)))
    func filterTagAll() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = try await Self.seed(db)
        let filter = HighlightBrowserFilter(tagIds: [Self.tagA, Self.tagB], tagMode: .all)
        let items = try await repo.browse(filter: filter, sort: .createdNewest)
        #expect(Self.ids(items) == [Self.h1])
    }

    @Test(.timeLimit(.minutes(1)))
    func filterColor() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = try await Self.seed(db)
        let filter = HighlightBrowserFilter(colors: [.yellow])
        let items = try await repo.browse(filter: filter, sort: .createdNewest)
        #expect(Self.ids(items) == [Self.h6, Self.h1])
    }

    @Test(.timeLimit(.minutes(1)))
    func filterHasNoteTrue() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = try await Self.seed(db)
        let items = try await repo.browse(filter: HighlightBrowserFilter(hasNote: true), sort: .createdNewest)
        #expect(Self.ids(items) == [Self.h2, Self.h5])
    }

    @Test(.timeLimit(.minutes(1)))
    func filterHasNoteFalse() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = try await Self.seed(db)
        let items = try await repo.browse(filter: HighlightBrowserFilter(hasNote: false), sort: .createdNewest)
        // h4 has a whitespace-only note, which counts as no note.
        #expect(Self.ids(items) == [Self.h4, Self.h3, Self.h6, Self.h1])
    }

    @Test(.timeLimit(.minutes(1)))
    func filterView() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = try await Self.seed(db)
        let items = try await repo.browse(filter: HighlightBrowserFilter(views: [.pdf]), sort: .createdNewest)
        #expect(Self.ids(items) == [Self.h3, Self.h5, Self.h1])
    }

    @Test(.timeLimit(.minutes(1)))
    func filterDateRange() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = try await Self.seed(db)
        let t0 = TestData.referenceDate
        let filter = HighlightBrowserFilter(
            createdFrom: t0.addingTimeInterval(2 * Self.day),
            createdBefore: t0.addingTimeInterval(3 * Self.day)
        )
        let items = try await repo.browse(filter: filter, sort: .createdNewest)
        #expect(Self.ids(items) == [Self.h4, Self.h3])
    }

    @Test(.timeLimit(.minutes(1)))
    func filtersCombine() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = try await Self.seed(db)
        let filter = HighlightBrowserFilter(
            categoryIds: [BuiltinCategory.paper.id],
            colors: [.yellow, .pink],
            hasNote: false
        )
        let items = try await repo.browse(filter: filter, sort: .createdNewest)
        #expect(Self.ids(items) == [Self.h4, Self.h6])
    }

    @Test(.timeLimit(.minutes(1)))
    func sortCreatedNewest() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = try await Self.seed(db)
        let items = try await repo.browse(filter: HighlightBrowserFilter(), sort: .createdNewest)
        #expect(Self.ids(items) == [Self.h4, Self.h3, Self.h6, Self.h2, Self.h5, Self.h1])
    }

    @Test(.timeLimit(.minutes(1)))
    func sortDocumentPosition() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = try await Self.seed(db)
        let items = try await repo.browse(filter: HighlightBrowserFilter(), sort: .documentPosition)
        // "alpha lectures" sorts before "Beta paper" case-insensitively; within a document, by positionKey.
        #expect(Self.ids(items) == [Self.h1, Self.h2, Self.h5, Self.h6, Self.h3, Self.h4])
    }

    @Test(.timeLimit(.minutes(1)))
    func sortColor() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = try await Self.seed(db)
        let items = try await repo.browse(filter: HighlightBrowserFilter(), sort: .color)
        #expect(Self.ids(items) == [Self.h6, Self.h1, Self.h2, Self.h3, Self.h4, Self.h5])
    }

    @Test(.timeLimit(.minutes(1)))
    func itemsCarryTitleCategoryTags() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = try await Self.seed(db)
        let items = try await repo.browse(filter: HighlightBrowserFilter(), sort: .createdNewest)
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.highlight.id, $0) })

        let first = try #require(byId[Self.h1])
        #expect(first.documentTitle == "alpha lectures")
        #expect(first.categoryId == BuiltinCategory.lectureSlides.id)
        #expect(first.tagIds == [Self.tagA, Self.tagB])
        #expect(first.tagNames == ["apple", "Banana"])

        let second = try #require(byId[Self.h2])
        #expect(second.tagNames == ["Banana"])

        let third = try #require(byId[Self.h3])
        #expect(third.documentTitle == "Beta paper")
        #expect(third.categoryId == BuiltinCategory.paper.id)
        #expect(third.tagNames == ["apple"])

        let untagged = try #require(byId[Self.h4])
        #expect(untagged.tagIds.isEmpty)
        #expect(untagged.tagNames.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func observeBrowseEmits() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = try await Self.seed(db)
        let observation = repo.observeBrowse(filter: HighlightBrowserFilter(), sort: .createdNewest)
        var iterator = observation.makeAsyncIterator()

        let initial = try #require(try await iterator.next())
        #expect(initial.count == 6)

        try await repo.updateColor(id: Self.h1, color: .purple, at: TestData.referenceDate.addingTimeInterval(100))
        let updated = try #require(try await iterator.next())
        let h1Item = try #require(updated.first { $0.highlight.id == Self.h1 })
        #expect(h1Item.highlight.color == .purple)
    }

    @Test(.timeLimit(.minutes(1)))
    func onlyIdsLimitsTheItems() async throws {
        let db = try AppDatabase.makeInMemory()
        _ = try await Self.seed(db)
        let items = try await db.writer.read { db in
            try HighlightBrowseSQL.items(
                db,
                filter: HighlightBrowserFilter(),
                sort: .documentPosition,
                onlyIds: [Self.h1, Self.h3]
            )
        }
        #expect(Self.ids(items) == [Self.h1, Self.h3])
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.highlight.id, $0) })
        #expect(byId[Self.h1]?.tagNames == ["apple", "Banana"])
        #expect(byId[Self.h3]?.tagNames == ["apple"])

        let none = try await db.writer.read { db in
            try HighlightBrowseSQL.items(db, filter: HighlightBrowserFilter(), sort: .documentPosition, onlyIds: [])
        }
        #expect(none.isEmpty)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func observeBrowseFollowsTagAndDocumentChanges() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = try await Self.seed(db)
        let observation = repo.observeBrowse(filter: HighlightBrowserFilter(), sort: .createdNewest)
        var iterator = observation.makeAsyncIterator()
        _ = try #require(try await iterator.next())

        // (a) A tag added to h4 shows up in its row.
        try await TagRepository(database: db).addTag(Self.tagB, toHighlights: [Self.h4])
        var afterTag: [HighlightListItem]?
        for _ in 0..<5 {
            let next = try #require(try await iterator.next())
            if next.first(where: { $0.highlight.id == Self.h4 })?.tagNames.contains("apple") == true {
                afterTag = next
                break
            }
        }
        let tagged = try #require(afterTag?.first { $0.highlight.id == Self.h4 })
        #expect(tagged.tagNames == ["apple"])
        #expect(tagged.tagIds == [Self.tagB])

        // (b) Moving the document of h3 to another category shows the new categoryId.
        try await DocumentRepository(database: db).updateMetadata(
            id: Self.docB, title: "Beta paper", author: "", categoryId: BuiltinCategory.lectureSlides.id
        )
        var afterMove: [HighlightListItem]?
        for _ in 0..<5 {
            let next = try #require(try await iterator.next())
            if next.first(where: { $0.highlight.id == Self.h3 })?.categoryId == BuiltinCategory.lectureSlides.id {
                afterMove = next
                break
            }
        }
        let moved = try #require(afterMove?.first { $0.highlight.id == Self.h3 })
        #expect(moved.categoryId == BuiltinCategory.lectureSlides.id)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func datesAreBoundAsNumbers() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = try await Self.seed(db)

        let future = HighlightBrowserFilter(createdFrom: Date(timeIntervalSince1970: 4_000_000_000))
        let futureItems = try await repo.browse(filter: future, sort: .createdNewest)
        #expect(futureItems.isEmpty)

        let past = HighlightBrowserFilter(createdFrom: Date(timeIntervalSince1970: 0))
        let pastItems = try await repo.browse(filter: past, sort: .createdNewest)
        #expect(pastItems.count == 6)
    }
}
