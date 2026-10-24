import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite struct FTSIntegrityTests {
    @Test func cleanDatabasePasses() async throws {
        let database = try AppDatabase.makeInMemory()
        try await database.writer.write { db in
            try FTSIntegrity.check(db)
        }

        let document = TestData.document(id: "C1000000-0000-4000-8000-000000000001", title: "Quantum")
        let highlight = TestData.highlight(
            documentId: document.id,
            id: "C2000000-0000-4000-8000-000000000001",
            text: "photosynthesis",
            note: "chloroplast"
        )
        let text = DocumentText(
            documentId: document.id,
            unitIndex: 0,
            startOffset: 0,
            text: "Photosynthesis occurs in chloroplasts"
        )
        let note = DocumentNote(
            documentId: document.id,
            body: "Exam covers mitochondria",
            updatedAt: TestData.referenceDate
        )
        try await database.writer.write { db in
            try document.insert(db)
            try highlight.insert(db)
            try text.insert(db)
            try note.insert(db)
        }

        var edited = highlight
        edited.note = "mitochondria"
        let updated = edited
        try await database.writer.write { db in
            try updated.update(db)
        }

        try await database.writer.write { db in
            _ = try LibraryDocument.deleteOne(db, key: document.id)
        }

        try await database.writer.write { db in
            try FTSIntegrity.check(db)
        }
    }

    @Test func replaceDesyncIsDetected() async throws {
        let database = try AppDatabase.makeInMemory()
        let categoryId = BuiltinCategory.paper.id
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO document (id, title, author, categoryId, fileType, fileHash, originalFilename, storedPath, addedAt)
                    VALUES ('A0000000-0000-4000-8000-0000000000A1', 'Quantum', '', ?, 'pdf', 'h1', 'a.pdf', 'A/original.pdf', 1790000000)
                    """,
                arguments: [categoryId]
            )
            // This is why ADR-0012 forbids REPLACE.
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO document (id, title, author, categoryId, fileType, fileHash, originalFilename, storedPath, addedAt)
                    VALUES ('A0000000-0000-4000-8000-0000000000B2', 'Biology', '', ?, 'pdf', 'h1', 'b.pdf', 'B/original.pdf', 1790000000)
                    """,
                arguments: [categoryId]
            )
        }

        let (documentCount, staleMatches) = try await database.reader.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM document") ?? -1,
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM document_fts WHERE document_fts MATCH ?",
                    arguments: ["Quantum"]
                ) ?? -1
            )
        }
        #expect(documentCount == 1)
        #expect(staleMatches == 1)

        await #expect(throws: DatabaseError.self) {
            try await database.writer.write { db in
                try FTSIntegrity.check(db)
            }
        }
    }
}
