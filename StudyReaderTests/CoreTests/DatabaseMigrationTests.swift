import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("Database migration v1")
struct DatabaseMigrationTests {
    private static let categoryId = BuiltinCategory.paper.id

    private static func insertDocument(_ db: Database, id: String, title: String = "Doc") throws {
        try db.execute(
            sql: """
                INSERT INTO document (id, title, categoryId, fileType, fileHash, originalFilename, storedPath, addedAt)
                VALUES (?, ?, ?, 'pdf', ?, 'doc.pdf', ?, 1790000000)
                """,
            arguments: [id, title, categoryId, "hash-\(id)", "\(id)/original.pdf"]
        )
    }

    private static func insertHighlight(_ db: Database, id: String, documentId: String) throws {
        try db.execute(
            sql: """
                INSERT INTO highlight (id, documentId, kind, view, positionKey, anchor, createdAt, updatedAt)
                VALUES (?, ?, 'text', 'pdf', 1.0, '{}', 1790000000, 1790000000)
                """,
            arguments: [id, documentId]
        )
    }

    @Test func v1CreatesAllTables() async throws {
        let db = try AppDatabase.makeInMemory()
        let names = try await db.reader.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type IN ('table', 'index')")
        }
        let expectedTables = [
            "category", "document", "documentText", "highlight", "tag", "highlightTag",
            "documentTag", "documentNote", "reviewCard", "reviewLog", "themedReview",
            "exportTarget", "highlightEmbedding",
            "documentText_fts", "highlight_fts", "documentNote_fts", "document_fts",
        ]
        for table in expectedTables {
            #expect(names.contains(table), "missing table \(table)")
        }
        let expectedIndexes = ["highlight_document", "highlightTag_tag", "reviewCard_due", "reviewCard_highlight"]
        for index in expectedIndexes {
            #expect(names.contains(index), "missing index \(index)")
        }
    }

    @Test func v1SeedsBuiltinCategories() async throws {
        let db = try AppDatabase.makeInMemory()
        let rows = try await db.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, name, frequency, sortOrder, isBuiltin, autoCreateCards
                FROM category ORDER BY sortOrder
                """).map { row -> (id: String, name: String, frequency: String, sortOrder: Int, isBuiltin: Int, autoCreateCards: Int) in
                    (row["id"], row["name"], row["frequency"], row["sortOrder"], row["isBuiltin"], row["autoCreateCards"])
                }
        }
        #expect(rows.count == 5)
        #expect(rows.count == BuiltinCategory.allCases.count)
        for (row, category) in zip(rows, BuiltinCategory.allCases) {
            #expect(row.id == category.id)
            #expect(row.name == category.name)
            #expect(row.frequency == category.frequency.rawValue)
            #expect(row.sortOrder == category.sortOrder)
            #expect(row.isBuiltin == 1)
            #expect(row.autoCreateCards == 1)
        }
    }

    @Test func reopeningDoesNotRemigrate() async throws {
        let fileStore = TestFileStore.make()
        defer { TestFileStore.remove(fileStore) }
        let first = try AppDatabase.makeShared(fileStore: fileStore)
        try await first.writer.write { db in
            try Self.insertDocument(db, id: "11111111-1111-1111-1111-111111111111")
        }

        let second = try AppDatabase.makeShared(fileStore: fileStore)
        let (count, applied, documents) = try await second.reader.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM category") ?? -1,
                try AppDatabase.migrator.appliedMigrations(db),
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM document") ?? -1
            )
        }
        #expect(count == 5)
        #expect(applied == ["v1"])
        #expect(documents == 1)
    }

    @Test func onDiskDatabaseUsesWAL() async throws {
        let fileStore = TestFileStore.make()
        defer { TestFileStore.remove(fileStore) }
        let db = try AppDatabase.makeShared(fileStore: fileStore)
        let mode = try await db.reader.read { db in
            try String.fetchOne(db, sql: "PRAGMA journal_mode")
        }
        #expect(mode == "wal")
        #expect(FileManager.default.fileExists(atPath: fileStore.databaseURL.path(percentEncoded: false)))
    }

    @Test func foreignKeysEnforced() async throws {
        let db = try AppDatabase.makeInMemory()
        let error = try await #require(throws: DatabaseError.self) {
            try await db.writer.write { db in
                try Self.insertHighlight(db, id: "22222222-2222-2222-2222-222222222222", documentId: "missing")
            }
        }
        #expect(error.resultCode == .SQLITE_CONSTRAINT)
    }

    @Test func checkConstraintsEnforced() async throws {
        let db = try AppDatabase.makeInMemory()
        let documentId = "33333333-3333-3333-3333-333333333333"
        try await db.writer.write { db in
            try Self.insertDocument(db, id: documentId)
        }

        let badFileType = try await #require(throws: DatabaseError.self) {
            try await db.writer.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO document (id, title, categoryId, fileType, fileHash, originalFilename, storedPath, addedAt)
                        VALUES (?, 'Bad', ?, 'docx', 'hash-bad', 'bad.docx', 'bad', 1790000000)
                        """,
                    arguments: ["44444444-4444-4444-4444-444444444444", Self.categoryId]
                )
            }
        }
        #expect(badFileType.resultCode == .SQLITE_CONSTRAINT)

        let badColor = try await #require(throws: DatabaseError.self) {
            try await db.writer.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO highlight (id, documentId, kind, view, color, positionKey, anchor, createdAt, updatedAt)
                        VALUES ('55555555-5555-5555-5555-555555555555', ?, 'text', 'pdf', 5, 1.0, '{}', 1790000000, 1790000000)
                        """,
                    arguments: [documentId]
                )
            }
        }
        #expect(badColor.resultCode == .SQLITE_CONSTRAINT)

        let badFrequency = try await #require(throws: DatabaseError.self) {
            try await db.writer.write { db in
                try db.execute(
                    sql: "INSERT INTO category (id, name, frequency) VALUES (?, 'Sometimes', 'sometimes')",
                    arguments: ["66666666-6666-6666-6666-666666666666"]
                )
            }
        }
        #expect(badFrequency.resultCode == .SQLITE_CONSTRAINT)
    }

    @Test func deletingDocumentCascades() async throws {
        let db = try AppDatabase.makeInMemory()
        let documentId = "77777777-7777-7777-7777-777777777777"
        let highlightId = "88888888-8888-8888-8888-888888888888"
        let tagId = "99999999-9999-9999-9999-999999999999"
        let cardId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

        try await db.writer.write { db in
            try Self.insertDocument(db, id: documentId)
            try db.execute(
                sql: "INSERT INTO documentText (documentId, unitIndex, startOffset, text) VALUES (?, 0, 0, 'page text')",
                arguments: [documentId]
            )
            try Self.insertHighlight(db, id: highlightId, documentId: documentId)
            try db.execute(
                sql: "INSERT INTO tag (id, name, createdAt) VALUES (?, 'exam', 1790000000)",
                arguments: [tagId]
            )
            try db.execute(
                sql: "INSERT INTO highlightTag (highlightId, tagId) VALUES (?, ?)",
                arguments: [highlightId, tagId]
            )
            try db.execute(
                sql: "INSERT INTO documentTag (documentId, tagId) VALUES (?, ?)",
                arguments: [documentId, tagId]
            )
            try db.execute(
                sql: "INSERT INTO documentNote (documentId, body, updatedAt) VALUES (?, 'note body', 1790000000)",
                arguments: [documentId]
            )
            try db.execute(
                sql: """
                    INSERT INTO reviewCard (id, highlightId, cardType, fsrsCard, dueAt, state, createdAt)
                    VALUES (?, ?, 'passive', '{}', 1790000000, 'new', 1790000000)
                    """,
                arguments: [cardId, highlightId]
            )
            try db.execute(
                sql: """
                    INSERT INTO reviewLog (id, cardId, rating, reviewedAt, sessionKind, fsrsLog)
                    VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', ?, 3, 1790000000, 'daily', '{}')
                    """,
                arguments: [cardId]
            )
            try db.execute(
                sql: """
                    INSERT INTO highlightEmbedding (highlightId, modelId, dimension, vector, sourceHash)
                    VALUES (?, 'model', 1, x'00000000', 'hash')
                    """,
                arguments: [highlightId]
            )
        }

        try await db.writer.write { db in
            try db.execute(sql: "DELETE FROM document WHERE id = ?", arguments: [documentId])
        }
        try await db.writer.write { db in try FTSIntegrity.check(db) }

        let counts = try await db.reader.read { db -> [String: Int] in
            let queries: [(String, String)] = [
                ("documentText", "SELECT COUNT(*) FROM documentText WHERE documentId = '\(documentId)'"),
                ("highlight", "SELECT COUNT(*) FROM highlight WHERE documentId = '\(documentId)'"),
                ("highlightTag", "SELECT COUNT(*) FROM highlightTag WHERE highlightId = '\(highlightId)'"),
                ("documentTag", "SELECT COUNT(*) FROM documentTag WHERE documentId = '\(documentId)'"),
                ("documentNote", "SELECT COUNT(*) FROM documentNote WHERE documentId = '\(documentId)'"),
                ("reviewCard", "SELECT COUNT(*) FROM reviewCard WHERE highlightId = '\(highlightId)'"),
                ("reviewLog", "SELECT COUNT(*) FROM reviewLog WHERE cardId = '\(cardId)'"),
                ("highlightEmbedding", "SELECT COUNT(*) FROM highlightEmbedding WHERE highlightId = '\(highlightId)'"),
                ("tag", "SELECT COUNT(*) FROM tag WHERE id = '\(tagId)'"),
            ]
            var result: [String: Int] = [:]
            for (name, sql) in queries {
                result[name] = try Int.fetchOne(db, sql: sql) ?? -1
            }
            return result
        }
        for table in ["documentText", "highlight", "highlightTag", "documentTag", "documentNote",
                      "reviewCard", "reviewLog", "highlightEmbedding"] {
            #expect(counts[table] == 0, "\(table) should be cascade-deleted")
        }
        #expect(counts["tag"] == 1)
    }

    @Test func categoryDeleteRestricted() async throws {
        let db = try AppDatabase.makeInMemory()
        let documentId = "cccccccc-cccc-cccc-cccc-cccccccccccc"
        try await db.writer.write { db in
            try Self.insertDocument(db, id: documentId)
        }
        _ = try await #require(throws: DatabaseError.self) {
            try await db.writer.write { db in
                try db.execute(sql: "DELETE FROM category WHERE id = ?", arguments: [Self.categoryId])
            }
        }
        let remaining = try await db.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM category")
        }
        #expect(remaining == 5)
    }
}
