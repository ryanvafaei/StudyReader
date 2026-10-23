import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("CategoryRepository")
struct CategoryRepositoryTests {
    @Test func fetchAllReturnsBuiltinsInOrder() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = CategoryRepository(database: db)

        let categories = try await repo.fetchAll()

        #expect(categories.map(\.name) == ["Lecture slides", "Paper", "Book chapter", "Notes", "Other"])
    }

    @Test func fetchById() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = CategoryRepository(database: db)

        let other = try await repo.fetch(id: BuiltinCategory.other.id)
        let unknown = try await repo.fetch(id: "99999999-0000-0000-0000-000000000000")

        #expect(other?.name == "Other")
        #expect(unknown == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func observeAllEmitsChanges() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = CategoryRepository(database: db)
        var iterator = repo.observeAll().makeAsyncIterator()

        let initial = try await iterator.next()
        #expect(initial?.count == 5)

        let custom = DocumentCategory(
            id: "30000000-0000-0000-0000-0000000000c1",
            name: "Thesis reading",
            sortOrder: 10
        )
        try await db.writer.write { db in
            try custom.insert(db)
        }

        let updated = try await iterator.next()
        #expect(updated?.count == 6)
        #expect(updated?.last?.id == custom.id)
    }
}
