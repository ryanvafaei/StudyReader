import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("FTS5 schema v1")
struct FTSSchemaTests {
    private static let categoryId = BuiltinCategory.paper.id

    private static func insertDocument(_ db: Database, id: String, title: String = "Doc", author: String = "") throws {
        try db.execute(
            sql: """
                INSERT INTO document (id, title, author, categoryId, fileType, fileHash, originalFilename, storedPath, addedAt)
                VALUES (?, ?, ?, ?, 'pdf', ?, 'doc.pdf', ?, 1790000000)
                """,
            arguments: [id, title, author, categoryId, "hash-\(id)", "\(id)/original.pdf"]
        )
    }

    private static func insertHighlight(
        _ db: Database,
        id: String,
        documentId: String,
        text: String = "",
        note: String = ""
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO highlight (id, documentId, kind, view, text, note, positionKey, anchor, createdAt, updatedAt)
                VALUES (?, ?, 'text', 'pdf', ?, ?, 1.0, '{}', 1790000000, 1790000000)
                """,
            arguments: [id, documentId, text, note]
        )
    }

    /// rowids of FTS matches in `table` (an FTS table name) for `query`.
    private static func matchRowids(_ db: Database, table: String, query: String) throws -> [Int64] {
        try Int64.fetchAll(
            db,
            sql: "SELECT rowid FROM \(table) WHERE \(table) MATCH ?",
            arguments: [query]
        )
    }

    private static func rowid(_ db: Database, table: String, whereSQL: String, arguments: StatementArguments) throws -> Int64? {
        try Int64.fetchOne(db, sql: "SELECT rowid FROM \(table) WHERE \(whereSQL)", arguments: arguments)
    }

    @Test func highlightIndexFollowsChanges() async throws {
        let db = try AppDatabase.makeInMemory()
        let documentId = "10000000-0000-0000-0000-000000000001"
        let highlightId = "20000000-0000-0000-0000-000000000001"

        try await db.writer.write { db in
            try Self.insertDocument(db, id: documentId)
            try Self.insertHighlight(db, id: highlightId, documentId: documentId, note: "alpha")
        }

        try await db.reader.read { db in
            let rowid = try #require(try Self.rowid(db, table: "highlight", whereSQL: "id = ?", arguments: [highlightId]))
            let alpha = try Self.matchRowids(db, table: "highlight_fts", query: "alpha")
            #expect(alpha == [rowid])
        }

        try await db.writer.write { db in
            try db.execute(sql: "UPDATE highlight SET note = 'beta' WHERE id = ?", arguments: [highlightId])
        }

        try await db.reader.read { db in
            let rowid = try #require(try Self.rowid(db, table: "highlight", whereSQL: "id = ?", arguments: [highlightId]))
            let alpha = try Self.matchRowids(db, table: "highlight_fts", query: "alpha")
            let beta = try Self.matchRowids(db, table: "highlight_fts", query: "beta")
            #expect(alpha.isEmpty)
            #expect(beta == [rowid])
        }

        try await db.writer.write { db in
            try db.execute(sql: "DELETE FROM highlight WHERE id = ?", arguments: [highlightId])
        }

        let afterDelete = try await db.reader.read { db in
            try Self.matchRowids(db, table: "highlight_fts", query: "beta")
        }
        #expect(afterDelete.isEmpty)

        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func documentTextIndexed() async throws {
        let db = try AppDatabase.makeInMemory()
        let documentId = "10000000-0000-0000-0000-000000000002"
        try await db.writer.write { db in
            try Self.insertDocument(db, id: documentId)
            try db.execute(
                sql: "INSERT INTO documentText (documentId, unitIndex, startOffset, text) VALUES (?, 0, 0, 'Photosynthesis occurs in chloroplasts')",
                arguments: [documentId]
            )
        }
        try await db.reader.read { db in
            let rowid = try #require(try Self.rowid(
                db, table: "documentText", whereSQL: "documentId = ? AND unitIndex = 0", arguments: [documentId]
            ))
            let matches = try Self.matchRowids(db, table: "documentText_fts", query: "chloroplasts")
            #expect(matches == [rowid])
        }
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func documentNoteIndexed() async throws {
        let db = try AppDatabase.makeInMemory()
        let documentId = "10000000-0000-0000-0000-000000000003"
        try await db.writer.write { db in
            try Self.insertDocument(db, id: documentId)
            try db.execute(
                sql: "INSERT INTO documentNote (documentId, body, updatedAt) VALUES (?, 'Exam covers mitochondria', 1790000000)",
                arguments: [documentId]
            )
        }
        try await db.reader.read { db in
            let rowid = try #require(try Self.rowid(
                db, table: "documentNote", whereSQL: "documentId = ?", arguments: [documentId]
            ))
            let matches = try Self.matchRowids(db, table: "documentNote_fts", query: "mitochondria")
            #expect(matches == [rowid])
        }
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func documentTitleAuthorIndexed() async throws {
        let db = try AppDatabase.makeInMemory()
        let documentId = "10000000-0000-0000-0000-000000000004"
        try await db.writer.write { db in
            try Self.insertDocument(db, id: documentId, title: "Quantum Mechanics", author: "Schrödinger")
        }
        try await db.reader.read { db in
            let rowid = try #require(try Self.rowid(
                db, table: "document", whereSQL: "id = ?", arguments: [documentId]
            ))
            let byTitle = try Self.matchRowids(db, table: "document_fts", query: "Quantum")
            let byAuthor = try Self.matchRowids(db, table: "document_fts", query: "Schrodinger")
            #expect(byTitle == [rowid])
            #expect(byAuthor == [rowid])
        }
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func cascadeDeleteClearsIndex() async throws {
        let db = try AppDatabase.makeInMemory()
        let documentId = "10000000-0000-0000-0000-000000000005"
        let highlightId = "20000000-0000-0000-0000-000000000005"
        try await db.writer.write { db in
            try Self.insertDocument(db, id: documentId, title: "Okapi")
            try Self.insertHighlight(db, id: highlightId, documentId: documentId, text: "zebrafish", note: "xylophone")
            try db.execute(
                sql: "INSERT INTO documentText (documentId, unitIndex, startOffset, text) VALUES (?, 0, 0, 'quokka')",
                arguments: [documentId]
            )
            try db.execute(
                sql: "INSERT INTO documentNote (documentId, body, updatedAt) VALUES (?, 'narwhal', 1790000000)",
                arguments: [documentId]
            )
        }

        try await db.reader.read { db in
            let fish = try Self.matchRowids(db, table: "highlight_fts", query: "zebrafish")
            let quokka = try Self.matchRowids(db, table: "documentText_fts", query: "quokka")
            let narwhal = try Self.matchRowids(db, table: "documentNote_fts", query: "narwhal")
            #expect(fish.count == 1)
            #expect(quokka.count == 1)
            #expect(narwhal.count == 1)
            let okapi = try Self.matchRowids(db, table: "document_fts", query: "Okapi")
            #expect(okapi.count == 1)
        }

        try await db.writer.write { db in
            try db.execute(sql: "DELETE FROM document WHERE id = ?", arguments: [documentId])
        }

        try await db.reader.read { db in
            let fish = try Self.matchRowids(db, table: "highlight_fts", query: "zebrafish")
            let xylophone = try Self.matchRowids(db, table: "highlight_fts", query: "xylophone")
            let quokka = try Self.matchRowids(db, table: "documentText_fts", query: "quokka")
            let narwhal = try Self.matchRowids(db, table: "documentNote_fts", query: "narwhal")
            let okapi = try Self.matchRowids(db, table: "document_fts", query: "Okapi")
            #expect(fish.isEmpty)
            #expect(xylophone.isEmpty)
            #expect(quokka.isEmpty)
            #expect(narwhal.isEmpty)
            #expect(okapi.isEmpty)
        }
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func diacriticsRemoved() async throws {
        let db = try AppDatabase.makeInMemory()
        let documentId = "10000000-0000-0000-0000-000000000006"
        let highlightId = "20000000-0000-0000-0000-000000000006"
        try await db.writer.write { db in
            try Self.insertDocument(db, id: documentId)
            try Self.insertHighlight(db, id: highlightId, documentId: documentId, text: "café résumé")
        }
        try await db.reader.read { db in
            let rowid = try #require(try Self.rowid(
                db, table: "highlight", whereSQL: "id = ?", arguments: [highlightId]
            ))
            let cafe = try Self.matchRowids(db, table: "highlight_fts", query: "cafe")
            let resume = try Self.matchRowids(db, table: "highlight_fts", query: "resume")
            #expect(cafe == [rowid])
            #expect(resume == [rowid])
        }
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }
}
