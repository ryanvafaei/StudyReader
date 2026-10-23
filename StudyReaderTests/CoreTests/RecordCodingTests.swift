import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("Record column storage")
struct RecordCodingTests {
    private static func jsonObject(_ json: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return object as? [String: Any] ?? [:]
    }

    @Test func datesAndIdsStoredAsSchemaTypes() async throws {
        let db = try AppDatabase.makeInMemory()
        let document = TestData.document(id: "10000000-0000-0000-0000-000000000001")

        try await db.writer.write { db in
            try document.insert(db)
        }

        let stored = try await db.reader.read { db in
            try (
                addedType: String.fetchOne(db, sql: "SELECT typeof(addedAt) FROM document"),
                addedValue: Double.fetchOne(db, sql: "SELECT addedAt FROM document"),
                idType: String.fetchOne(db, sql: "SELECT typeof(id) FROM document"),
                idValue: String.fetchOne(db, sql: "SELECT id FROM document")
            )
        }
        #expect(stored.addedType == "real")
        #expect(stored.addedValue == 1_790_000_000)
        #expect(stored.idType == "text")
        #expect(stored.idValue == "10000000-0000-0000-0000-000000000001")
    }

    @Test func enumsStoredAsRawValues() async throws {
        let db = try AppDatabase.makeInMemory()
        let document = TestData.document(id: "10000000-0000-0000-0000-000000000002")
        let highlight = TestData.highlight(
            documentId: document.id, id: "20000000-0000-0000-0000-000000000002", color: .blue)
        let category = DocumentCategory(
            id: "30000000-0000-0000-0000-000000000002", name: "Reading", frequency: .high)

        try await db.writer.write { db in
            try document.insert(db)
            try highlight.insert(db)
            try category.insert(db)
        }

        let stored = try await db.reader.read { db in
            try (
                fileType: String.fetchOne(db, sql: "SELECT fileType FROM document WHERE id = ?", arguments: [document.id]),
                coverSource: String.fetchOne(db, sql: "SELECT coverSource FROM document WHERE id = ?", arguments: [document.id]),
                colorType: String.fetchOne(db, sql: "SELECT typeof(color) FROM highlight WHERE id = ?", arguments: [highlight.id]),
                color: Int.fetchOne(db, sql: "SELECT color FROM highlight WHERE id = ?", arguments: [highlight.id]),
                view: String.fetchOne(db, sql: "SELECT view FROM highlight WHERE id = ?", arguments: [highlight.id]),
                frequency: String.fetchOne(db, sql: "SELECT frequency FROM category WHERE id = ?", arguments: [category.id])
            )
        }
        #expect(stored.fileType == "pdf")
        #expect(stored.coverSource == "default")
        #expect(stored.colorType == "integer")
        #expect(stored.color == 2)
        #expect(stored.view == "markdown")
        #expect(stored.frequency == "high")
    }

    @Test func jsonColumnsStoredAsText() async throws {
        let db = try AppDatabase.makeInMemory()
        let document = TestData.document(id: "10000000-0000-0000-0000-000000000003")
        let highlight = TestData.highlight(
            documentId: document.id, id: "20000000-0000-0000-0000-000000000003")
        let text = DocumentText(
            documentId: document.id,
            unitIndex: 0,
            startOffset: 0,
            text: "Hello world",
            runs: [TextRun(start: 0, length: 5, bold: true, italic: false, mono: false, link: nil)]
        )

        try await db.writer.write { db in
            try document.insert(db)
            try highlight.insert(db)
            try text.insert(db)
        }

        let (anchorJSON, pdfPositionNull, runsType) = try await db.reader.read { db in
            try (
                String.fetchOne(db, sql: "SELECT anchor FROM highlight WHERE id = ?", arguments: [highlight.id]),
                Bool.fetchOne(db, sql: "SELECT pdfPosition IS NULL FROM document WHERE id = ?", arguments: [document.id]),
                String.fetchOne(db, sql: "SELECT typeof(runs) FROM documentText WHERE documentId = ?", arguments: [document.id])
            )
        }
        let anchor = try Self.jsonObject(try #require(anchorJSON))
        #expect(anchor["type"] as? String == "text")
        #expect(pdfPositionNull == true)
        #expect(runsType == "text")

        var positioned = document
        positioned.pdfPosition = PDFPosition(pageIndex: 3, offsetY: 120.5)
        let updated = positioned
        try await db.writer.write { db in
            try updated.update(db)
        }
        let pdfPositionJSON = try await db.reader.read { db in
            try String.fetchOne(db, sql: "SELECT pdfPosition FROM document WHERE id = ?", arguments: [document.id])
        }
        let pdfPosition = try Self.jsonObject(try #require(pdfPositionJSON))
        #expect(pdfPosition["pageIndex"] as? Int == 3)
    }
}
