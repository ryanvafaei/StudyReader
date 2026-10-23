import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("DocumentRepository")
struct DocumentRepositoryTests {
    @Test func insertAndFetch() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = DocumentRepository(database: db)
        let document = TestData.document(id: "10000000-0000-0000-0000-0000000000a1", title: "Lecture 1")

        try await repo.insert(document)
        let fetched = try await repo.fetch(id: document.id)
        let unknown = try await repo.fetch(id: "10000000-0000-0000-0000-0000000000ff")

        #expect(fetched == document)
        #expect(unknown == nil)
    }

    @Test func fetchAllNewestFirst() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = DocumentRepository(database: db)
        let oldest = TestData.document(
            id: "10000000-0000-0000-0000-0000000000a1",
            title: "Oldest",
            addedAt: Date(timeIntervalSince1970: 1_790_000_000)
        )
        let middle = TestData.document(
            id: "10000000-0000-0000-0000-0000000000a2",
            title: "Middle",
            addedAt: Date(timeIntervalSince1970: 1_790_000_100)
        )
        let newest = TestData.document(
            id: "10000000-0000-0000-0000-0000000000a3",
            title: "Newest",
            addedAt: Date(timeIntervalSince1970: 1_790_000_200)
        )
        for document in [middle, oldest, newest] {
            try await repo.insert(document)
        }

        let all = try await repo.fetchAll()

        #expect(all.map(\.title) == ["Newest", "Middle", "Oldest"])
    }

    @Test func duplicateHashThrows() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = DocumentRepository(database: db)
        let first = TestData.document(id: "10000000-0000-0000-0000-0000000000a1", fileHash: "same-hash")
        let duplicate = TestData.document(id: "10000000-0000-0000-0000-0000000000a2", fileHash: "same-hash")
        try await repo.insert(first)

        await #expect(throws: DatabaseError.self) {
            try await repo.insert(duplicate)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func observeAllEmitsAfterInsert() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = DocumentRepository(database: db)
        var iterator = repo.observeAll().makeAsyncIterator()

        let initial = try await iterator.next()
        #expect(initial == [])

        try await repo.insert(TestData.document(id: "10000000-0000-0000-0000-0000000000a1"))

        let updated = try await iterator.next()
        #expect(updated?.count == 1)
    }
}
