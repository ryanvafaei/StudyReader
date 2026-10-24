import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("TagRepository")
struct TagRepositoryTests {
    private static let documentOne = "10000000-0000-0000-0000-0000000000D1"
    private static let highlightOne = "20000000-0000-0000-0000-0000000000A1"
    private static let highlightTwo = "20000000-0000-0000-0000-0000000000A2"

    /// One document and two highlights on it, so link rows have valid foreign keys.
    private static func seed(_ db: AppDatabase) async throws {
        let documents = DocumentRepository(database: db)
        let highlights = HighlightRepository(database: db)
        try await documents.insert(TestData.document(id: documentOne, title: "One"))
        try await highlights.insert(TestData.highlight(documentId: documentOne, id: highlightOne, positionKey: 10))
        try await highlights.insert(TestData.highlight(documentId: documentOne, id: highlightTwo, positionKey: 20))
    }

    private static func highlightLinkCount(_ db: AppDatabase) async throws -> Int {
        try await db.writer.read { db in try HighlightTag.fetchCount(db) }
    }

    private static func documentLinkCount(_ db: AppDatabase) async throws -> Int {
        try await db.writer.read { db in try DocumentTag.fetchCount(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func normalizedNameRules() {
        #expect(TagRepository.normalizedName("  #Exam ") == "Exam")
        #expect(TagRepository.normalizedName("#") == nil)
        #expect(TagRepository.normalizedName("") == nil)
        #expect(TagRepository.normalizedName(String(repeating: "a", count: 40)) == String(repeating: "a", count: 40))
        #expect(TagRepository.normalizedName(String(repeating: "a", count: 41)) == nil)
        #expect(TagRepository.normalizedName("##x") == "#x")
    }

    @Test(.timeLimit(.minutes(1)))
    func uniqueness() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = TagRepository(database: db)
        let t0 = TestData.referenceDate

        let first = try await repo.findOrCreate(name: "Exam", at: t0)
        let second = try await repo.findOrCreate(name: "exam", at: t0)
        let third = try await repo.findOrCreate(name: "  #EXAM ", at: t0)

        #expect(second.id == first.id)
        #expect(third.id == first.id)
        #expect(first.name == "Exam")
        #expect(second.name == "Exam")
        #expect(third.name == "Exam")
        let rowCount = try await db.writer.read { db in try LibraryTag.fetchCount(db) }
        #expect(rowCount == 1)
        await #expect(throws: TagError.invalidName) {
            try await repo.findOrCreate(name: "", at: t0)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func renameMerge() async throws {
        let db = try AppDatabase.makeInMemory()
        try await Self.seed(db)
        let repo = TagRepository(database: db)
        let t0 = TestData.referenceDate
        let ml = try await repo.findOrCreate(name: "ML", at: t0)
        let machineLearning = try await repo.findOrCreate(name: "Machine Learning", at: t0)
        try await repo.addTag(ml.id, toHighlights: [Self.highlightOne])
        try await repo.addTag(machineLearning.id, toHighlights: [Self.highlightOne])
        try await repo.addTag(ml.id, toHighlights: [Self.highlightTwo])
        try await repo.setTags([ml.id], forDocument: Self.documentOne)

        await #expect(throws: TagError.duplicateName) {
            try await repo.rename(id: ml.id, to: "machine learning")
        }
        try await repo.rename(id: ml.id, to: "ml")
        let renamed = try await repo.fetchAll()
        #expect(renamed.map(\.name) == ["Machine Learning", "ml"])

        try await repo.merge(sourceId: ml.id, into: machineLearning.id)

        let h1Tags = try await repo.tags(forHighlight: Self.highlightOne)
        let h2Tags = try await repo.tags(forHighlight: Self.highlightTwo)
        let docTags = try await repo.tags(forDocument: Self.documentOne)
        #expect(h1Tags.map(\.id) == [machineLearning.id])
        #expect(h2Tags.map(\.name) == ["Machine Learning"])
        #expect(docTags.map(\.name) == ["Machine Learning"])
        #expect(try await Self.highlightLinkCount(db) == 2)
        #expect(try await Self.documentLinkCount(db) == 1)
        let remaining = try await repo.fetchAll()
        #expect(remaining.map(\.id) == [machineLearning.id])
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func deleteKeepsItems() async throws {
        let db = try AppDatabase.makeInMemory()
        try await Self.seed(db)
        let repo = TagRepository(database: db)
        let exam = try await repo.findOrCreate(name: "Exam", at: TestData.referenceDate)
        try await repo.addTag(exam.id, toHighlights: [Self.highlightOne])
        try await repo.setTags([exam.id], forDocument: Self.documentOne)

        try await repo.delete(id: exam.id)

        let highlight = try await HighlightRepository(database: db).fetch(id: Self.highlightOne)
        let document = try await DocumentRepository(database: db).fetch(id: Self.documentOne)
        #expect(highlight != nil)
        #expect(document != nil)
        #expect(try await repo.tags(forHighlight: Self.highlightOne).isEmpty)
        #expect(try await repo.tags(forDocument: Self.documentOne).isEmpty)
        #expect(try await repo.fetchAll().isEmpty)
        #expect(try await Self.highlightLinkCount(db) == 0)
        #expect(try await Self.documentLinkCount(db) == 0)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func setAndBulkTags() async throws {
        let db = try AppDatabase.makeInMemory()
        try await Self.seed(db)
        let repo = TagRepository(database: db)
        let t0 = TestData.referenceDate
        let a = try await repo.findOrCreate(name: "A", at: t0)
        let b = try await repo.findOrCreate(name: "B", at: t0)
        let c = try await repo.findOrCreate(name: "C", at: t0)

        try await repo.setTags([a.id, b.id], forHighlight: Self.highlightOne)
        try await repo.setTags([b.id], forHighlight: Self.highlightOne)
        #expect(try await repo.tags(forHighlight: Self.highlightOne).map(\.id) == [b.id])

        try await repo.addTag(c.id, toHighlights: [Self.highlightOne, Self.highlightTwo])
        try await repo.addTag(c.id, toHighlights: [Self.highlightOne, Self.highlightTwo])
        #expect(try await repo.tags(forHighlight: Self.highlightOne).map(\.id).sorted() == [b.id, c.id].sorted())
        #expect(try await repo.tags(forHighlight: Self.highlightTwo).map(\.id) == [c.id])
        #expect(try await Self.highlightLinkCount(db) == 3)

        try await repo.removeTag(c.id, fromHighlights: [Self.highlightOne])
        #expect(try await repo.tags(forHighlight: Self.highlightOne).map(\.id) == [b.id])
        #expect(try await repo.tags(forHighlight: Self.highlightTwo).map(\.id) == [c.id])

        try await repo.setTags([a.id, b.id], forDocument: Self.documentOne)
        try await repo.setTags([b.id], forDocument: Self.documentOne)
        #expect(try await repo.tags(forDocument: Self.documentOne).map(\.id) == [b.id])
        #expect(try await Self.documentLinkCount(db) == 1)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func observeUsageCounts() async throws {
        let db = try AppDatabase.makeInMemory()
        try await Self.seed(db)
        let repo = TagRepository(database: db)
        let t0 = TestData.referenceDate
        let exam = try await repo.findOrCreate(name: "Exam", at: t0)
        let week = try await repo.findOrCreate(name: "Week 3", at: t0)
        try await repo.addTag(exam.id, toHighlights: [Self.highlightOne])
        try await repo.setTags([week.id], forDocument: Self.documentOne)

        var iterator = repo.observeUsage().makeAsyncIterator()
        let first = try await iterator.next()
        let firstCounts = first?.map { ($0.tag.name, $0.highlightCount, $0.documentCount) }
        #expect(firstCounts?.count == 2)
        #expect(firstCounts?[0].0 == "Exam")
        #expect(firstCounts?[0].1 == 1)
        #expect(firstCounts?[0].2 == 0)
        #expect(firstCounts?[1].0 == "Week 3")
        #expect(firstCounts?[1].1 == 0)
        #expect(firstCounts?[1].2 == 1)

        try await repo.addTag(exam.id, toHighlights: [Self.highlightTwo])
        let second = try await iterator.next()
        let secondCounts = second?.map { ($0.tag.name, $0.highlightCount, $0.documentCount) }
        #expect(secondCounts?[0].0 == "Exam")
        #expect(secondCounts?[0].1 == 2)
        #expect(secondCounts?[0].2 == 0)
        #expect(secondCounts?[1].1 == 0)
        #expect(secondCounts?[1].2 == 1)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }
}
