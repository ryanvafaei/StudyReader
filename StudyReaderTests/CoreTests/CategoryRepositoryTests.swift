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

    @Test func createRenameDelete() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = CategoryRepository(database: db)
        let documentId = "10000000-0000-0000-0000-0000000000a1"
        try await DocumentRepository(database: db).insert(
            TestData.document(id: documentId, categoryId: BuiltinCategory.other.id)
        )

        let created = try await repo.create(name: "  Thesis  ")
        #expect(created.name == "Thesis")
        #expect(created.isBuiltin == false)
        #expect(created.frequency == .normal)
        #expect(created.autoCreateCards == true)
        #expect(created.sortOrder == 5)

        try await DocumentRepository(database: db).updateMetadata(
            id: documentId,
            title: "Doc",
            author: "",
            categoryId: created.id
        )

        try await repo.rename(id: created.id, to: "Dissertation")
        #expect(try await repo.fetch(id: created.id)?.name == "Dissertation")

        let moved = try await repo.delete(id: created.id)
        #expect(moved == 1)
        #expect(try await repo.fetch(id: created.id) == nil)
        let document = try #require(try await DocumentRepository(database: db).fetch(id: documentId))
        #expect(document.categoryId == BuiltinCategory.other.id)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func builtinsAreProtected() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = CategoryRepository(database: db)
        let paper = BuiltinCategory.paper.id

        await #expect(throws: CategoryError.builtinCategory) {
            try await repo.rename(id: paper, to: "Articles")
        }
        await #expect(throws: CategoryError.builtinCategory) {
            try await repo.delete(id: paper)
        }
        await #expect(throws: CategoryError.notFound) {
            try await repo.rename(id: "99999999-0000-0000-0000-000000000000", to: "X")
        }
        await #expect(throws: CategoryError.notFound) {
            try await repo.delete(id: "99999999-0000-0000-0000-000000000000")
        }
        #expect(try await repo.fetch(id: paper)?.name == "Paper")
    }

    @Test func validationAndUniqueness() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = CategoryRepository(database: db)
        let longName = String(repeating: "a", count: 41)
        let exactName = String(repeating: "b", count: 40)

        await #expect(throws: CategoryError.emptyName) {
            try await repo.create(name: "   ")
        }
        await #expect(throws: CategoryError.nameTooLong) {
            try await repo.create(name: longName)
        }
        #expect(try await repo.create(name: exactName).name == exactName)
        await #expect(throws: CategoryError.duplicateName) {
            try await repo.create(name: "paper")
        }
        let first = try await repo.create(name: "Thesis")
        let second = try await repo.create(name: "Reviews")
        await #expect(throws: CategoryError.duplicateName) {
            try await repo.rename(id: second.id, to: "THESIS")
        }
        // Renaming a category to its own name with different case is not a duplicate.
        try await repo.rename(id: first.id, to: "thesis")
        #expect(try await repo.fetch(id: first.id)?.name == "thesis")
    }

    @Test(.timeLimit(.minutes(1)))
    func observeUsageCounts() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = CategoryRepository(database: db)
        var iterator = repo.observeUsage().makeAsyncIterator()

        let initial = try await iterator.next()
        #expect(initial?.count == 5)
        #expect(initial?.allSatisfy { $0.documentCount == 0 } == true)

        // Both inserts in one transaction so the observation emits once with both rows.
        try await db.writer.write { db in
            try TestData.document(id: "10000000-0000-0000-0000-0000000000a1", categoryId: BuiltinCategory.notes.id).insert(db)
            try TestData.document(id: "10000000-0000-0000-0000-0000000000a2", categoryId: BuiltinCategory.notes.id, fileHash: "hash-2").insert(db)
        }

        let updated = try #require(try await iterator.next())
        let notes = try #require(updated.first { $0.category.id == BuiltinCategory.notes.id })
        let other = try #require(updated.first { $0.category.id == BuiltinCategory.other.id })
        #expect(notes.documentCount == 2)
        #expect(other.documentCount == 0)
        #expect(updated.map(\.category.name) == ["Lecture slides", "Paper", "Book chapter", "Notes", "Other"])
    }
}
