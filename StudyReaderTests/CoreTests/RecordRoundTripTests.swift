import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("Record round trips")
struct RecordRoundTripTests {
    private static let documentId = "10000000-0000-0000-0000-0000000000a1"

    private static func insertDocument(_ db: AppDatabase, id: String = documentId) async throws -> LibraryDocument {
        let document = TestData.document(id: id)
        try await db.writer.write { db in
            try document.insert(db)
        }
        return document
    }

    @Test func seededCategoriesDecode() async throws {
        let db = try AppDatabase.makeInMemory()

        let categories = try await db.reader.read { db in
            try DocumentCategory
                .filter(Column("isBuiltin") == true)
                .order(Column("sortOrder"))
                .fetchAll(db)
        }

        #expect(categories.count == BuiltinCategory.allCases.count)
        for builtin in BuiltinCategory.allCases {
            let match = categories.first { $0.id == builtin.id }
            #expect(match?.name == builtin.name)
            #expect(match?.frequency == builtin.frequency)
            #expect(match?.sortOrder == builtin.sortOrder)
            #expect(match?.isBuiltin == true)
        }
    }

    @Test func categoryRoundTrip() async throws {
        let db = try AppDatabase.makeInMemory()
        let category = DocumentCategory(
            id: "30000000-0000-0000-0000-0000000000c1",
            name: "Thesis reading",
            isBuiltin: false,
            frequency: .off,
            autoCreateCards: false,
            sortOrder: 7
        )

        try await db.writer.write { db in
            try category.insert(db)
        }
        let fetched = try await db.reader.read { db in
            try DocumentCategory.fetchOne(db, key: category.id)
        }
        #expect(fetched == category)
    }

    @Test func documentRoundTrip() async throws {
        let db = try AppDatabase.makeInMemory()
        let document = LibraryDocument(
            id: Self.documentId,
            title: "Full document",
            author: "A. Author",
            categoryId: BuiltinCategory.paper.id,
            fileType: .pdf,
            fileHash: "sha256-full",
            originalFilename: "full.pdf",
            originalBookmark: Data([0x01, 0x02, 0x03, 0xFF]),
            storedPath: "\(Self.documentId)/original.pdf",
            pageCount: 42,
            coverPath: "\(Self.documentId)/cover.png",
            coverSource: .custom,
            extractionStatus: .done,
            extractionVersion: 3,
            pdfPosition: PDFPosition(pageIndex: 5, offsetY: 310.25),
            textPosition: 1200,
            progress: 0.5,
            addedAt: TestData.referenceDate,
            lastOpenedAt: TestData.referenceDate.addingTimeInterval(3600)
        )

        try await db.writer.write { db in
            try document.insert(db)
        }
        let fetched = try await db.reader.read { db in
            try LibraryDocument.fetchOne(db, key: document.id)
        }
        #expect(fetched == document)
    }

    @Test func documentTextRoundTrip() async throws {
        let db = try AppDatabase.makeInMemory()
        _ = try await Self.insertDocument(db)
        let text = DocumentText(
            documentId: Self.documentId,
            unitIndex: 2,
            startOffset: 4096,
            text: "Bold and linked text",
            runs: [
                TextRun(start: 0, length: 4, bold: true, italic: false, mono: false, link: nil),
                TextRun(start: 9, length: 6, bold: false, italic: true, mono: true, link: "https://example.com")
            ]
        )

        try await db.writer.write { db in
            try text.insert(db)
        }
        let fetched = try await db.reader.read { db in
            try DocumentText.fetchOne(
                db,
                sql: "SELECT * FROM documentText WHERE documentId = ? AND unitIndex = ?",
                arguments: [text.documentId, text.unitIndex]
            )
        }
        #expect(fetched == text)
    }

    @Test func pdfHighlightRoundTrip() async throws {
        let db = try AppDatabase.makeInMemory()
        _ = try await Self.insertDocument(db)
        let anchor = HighlightAnchor.pdf(PDFAnchor(
            pages: [
                PDFAnchor.PageRects(pageIndex: 3, rects: [CGRectCodable(x: 72, y: 540, width: 300, height: 14)]),
                PDFAnchor.PageRects(pageIndex: 4, rects: [CGRectCodable(x: 72, y: 700, width: 120, height: 14)])
            ],
            text: "Spanning two pages",
            prefix: "before ",
            suffix: " after"
        ))
        let highlight = Highlight(
            id: "20000000-0000-0000-0000-0000000000b1",
            documentId: Self.documentId,
            kind: .text,
            view: .pdf,
            color: .pink,
            text: "Spanning two pages",
            richText: "Spanning two pages",
            editedText: "Edited",
            note: "a note",
            pageIndex: 3,
            positionKey: 3.54,
            anchor: anchor,
            anchorStatus: .orphaned,
            imagePath: nil,
            createdAt: TestData.referenceDate,
            updatedAt: TestData.referenceDate.addingTimeInterval(60)
        )

        try await db.writer.write { db in
            try highlight.insert(db)
        }
        let fetched = try await db.reader.read { db in
            try Highlight.fetchOne(db, key: highlight.id)
        }
        #expect(fetched == highlight)
    }

    @Test func imageHighlightRoundTrip() async throws {
        let db = try AppDatabase.makeInMemory()
        _ = try await Self.insertDocument(db)
        let highlight = Highlight(
            id: "20000000-0000-0000-0000-0000000000b2",
            documentId: Self.documentId,
            kind: .image,
            view: .pdf,
            color: .green,
            pageIndex: 7,
            positionKey: 7.1,
            anchor: .image(ImageAnchor(pageIndex: 7, rect: CGRectCodable(x: 10, y: 20, width: 200, height: 150))),
            imagePath: "\(Self.documentId)/highlights/b2.png",
            createdAt: TestData.referenceDate,
            updatedAt: TestData.referenceDate
        )

        try await db.writer.write { db in
            try highlight.insert(db)
        }
        let fetched = try await db.reader.read { db in
            try Highlight.fetchOne(db, key: highlight.id)
        }
        #expect(fetched == highlight)
    }

    @Test func taggingRoundTrip() async throws {
        let db = try AppDatabase.makeInMemory()
        _ = try await Self.insertDocument(db)
        let highlight = TestData.highlight(documentId: Self.documentId, id: "20000000-0000-0000-0000-0000000000c3")
        let tag = TestData.tag(name: "Exam", id: "40000000-0000-0000-0000-0000000000d1")
        let highlightTag = HighlightTag(highlightId: highlight.id, tagId: tag.id)
        let documentTag = DocumentTag(documentId: Self.documentId, tagId: tag.id)

        try await db.writer.write { db in
            try highlight.insert(db)
            try tag.insert(db)
            try highlightTag.insert(db)
            try documentTag.insert(db)
        }

        let fetched = try await db.reader.read { db in
            try (
                tag: LibraryTag.fetchOne(db, key: tag.id),
                highlightTag: HighlightTag.fetchAll(db),
                documentTag: DocumentTag.fetchAll(db)
            )
        }
        #expect(fetched.tag == tag)
        #expect(fetched.highlightTag == [highlightTag])
        #expect(fetched.documentTag == [documentTag])
    }

    @Test func documentNoteRoundTrip() async throws {
        let db = try AppDatabase.makeInMemory()
        _ = try await Self.insertDocument(db)
        let note = DocumentNote(
            documentId: Self.documentId,
            body: "Overall notes for the chapter",
            updatedAt: TestData.referenceDate
        )

        try await db.writer.write { db in
            try note.insert(db)
        }
        let fetched = try await db.reader.read { db in
            try DocumentNote.fetchOne(db, key: note.documentId)
        }
        #expect(fetched == note)
    }

    @Test func updateKeepsRowAndIndex() async throws {
        let db = try AppDatabase.makeInMemory()
        _ = try await Self.insertDocument(db)
        let original = TestData.highlight(documentId: Self.documentId, id: "20000000-0000-0000-0000-0000000000e1", text: "photosynthesis")
        try await db.writer.write { db in
            try original.insert(db)
        }

        var edited = original
        edited.note = "chloroplast detail"
        let updated = edited
        try await db.writer.write { db in
            try updated.update(db)
        }

        let result = try await db.reader.read { db in
            try (
                count: Int.fetchOne(db, sql: "SELECT COUNT(*) FROM highlight"),
                noteMatches: Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM highlight_fts WHERE highlight_fts MATCH ?",
                    arguments: ["chloroplast"]
                ),
                fetched: Highlight.fetchOne(db, key: updated.id)
            )
        }
        #expect(result.count == 1)
        #expect(result.noteMatches == 1)
        #expect(result.fetched == updated)
    }

    @Test func tagNameUniqueNoCase() async throws {
        let db = try AppDatabase.makeInMemory()
        try await db.writer.write { db in
            try TestData.tag(name: "Exam").insert(db)
        }

        await #expect(throws: DatabaseError.self) {
            try await db.writer.write { db in
                try TestData.tag(name: "exam").insert(db)
            }
        }
    }
}
