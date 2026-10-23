import Foundation
import GRDB
import Testing
@testable import StudyReader

/// Guards ADR-0012 "Writes" and "Dedupe": upsert only with the primary key as conflict target.
/// GRDB's default upsert would turn a UNIQUE conflict on `fileHash` or `name` into a silent overwrite.
@Suite("UpsertConvention")
struct UpsertConventionTests {
    private let idA = "10000000-0000-0000-0000-0000000000a1"
    private let idB = "10000000-0000-0000-0000-0000000000a2"

    @Test func primaryKeyUpsertInsertsNewRow() async throws {
        let database = try AppDatabase.makeInMemory()
        let document = TestData.document(id: idA)

        let (returned, fetched) = try await database.writer.write { db in
            let returned = try document.upsertAndFetch(db, onConflict: ["id"])
            let fetched = try LibraryDocument.fetchOne(db, key: idA)
            return (returned, fetched)
        }

        #expect(returned == document)
        #expect(fetched == document)
    }

    @Test func primaryKeyUpsertUpdatesExistingRow() async throws {
        let database = try AppDatabase.makeInMemory()
        let original = TestData.document(id: idA)
        try await database.writer.write { db in
            try original.insert(db)
        }
        var renamed = original
        renamed.title = "Renamed"
        let edited = renamed

        let (fetched, count) = try await database.writer.write { db in
            _ = try edited.upsertAndFetch(db, onConflict: ["id"])
            let fetched = try LibraryDocument.fetchOne(db, key: idA)
            let count = try LibraryDocument.fetchCount(db)
            return (fetched, count)
        }

        #expect(fetched?.title == "Renamed")
        #expect(fetched?.storedPath == original.storedPath)
        #expect(count == 1)
    }

    @Test func primaryKeyUpsertWithDuplicateFileHashThrows() async throws {
        let database = try AppDatabase.makeInMemory()
        let original = TestData.document(id: idA, title: "Quantum", fileHash: "same")
        let duplicate = TestData.document(id: idB, title: "Biology", fileHash: "same")
        try await database.writer.write { db in
            try original.insert(db)
        }

        let error = await #expect(throws: DatabaseError.self) {
            try await database.writer.write { db in
                _ = try duplicate.upsertAndFetch(db, onConflict: ["id"])
            }
        }
        #expect(error?.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE)

        let (fetchedA, fetchedB, count) = try await database.writer.read { db in
            let fetchedA = try LibraryDocument.fetchOne(db, key: idA)
            let fetchedB = try LibraryDocument.fetchOne(db, key: idB)
            let count = try LibraryDocument.fetchCount(db)
            return (fetchedA, fetchedB, count)
        }
        #expect(fetchedA == original)
        #expect(fetchedA?.storedPath == "\(idA)/original.pdf")
        #expect(fetchedB == nil)
        #expect(count == 1)
    }

    @Test func primaryKeyUpsertWithDuplicateTagNameThrows() async throws {
        let database = try AppDatabase.makeInMemory()
        let original = TestData.tag(name: "Exam", id: idA)
        let duplicate = TestData.tag(name: "exam", id: idB)
        try await database.writer.write { db in
            try original.insert(db)
        }

        let error = await #expect(throws: DatabaseError.self) {
            try await database.writer.write { db in
                _ = try duplicate.upsertAndFetch(db, onConflict: ["id"])
            }
        }
        #expect(error?.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE)

        let (nameA, fetchedB, count) = try await database.writer.read { db in
            let nameA = try LibraryTag.fetchOne(db, key: idA)?.name
            let fetchedB = try LibraryTag.fetchOne(db, key: idB)
            let count = try LibraryTag.fetchCount(db)
            return (nameA, fetchedB, count)
        }
        #expect(nameA == "Exam")
        #expect(fetchedB == nil)
        #expect(count == 1)
    }

    @Test func saveWithDuplicateFileHashThrows() async throws {
        let database = try AppDatabase.makeInMemory()
        let original = TestData.document(id: idA, title: "Quantum", fileHash: "same")
        let duplicate = TestData.document(id: idB, title: "Biology", fileHash: "same")
        try await database.writer.write { db in
            try original.insert(db)
        }
        let pending = duplicate

        let error = await #expect(throws: DatabaseError.self) {
            try await database.writer.write { db in
                let record = pending
                try record.save(db)
            }
        }
        #expect(error?.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE)

        let (fetchedA, fetchedB) = try await database.writer.read { db in
            let fetchedA = try LibraryDocument.fetchOne(db, key: idA)
            let fetchedB = try LibraryDocument.fetchOne(db, key: idB)
            return (fetchedA, fetchedB)
        }
        #expect(fetchedA == original)
        #expect(fetchedB == nil)
    }
}
