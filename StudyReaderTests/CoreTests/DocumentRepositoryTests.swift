import Foundation
import GRDB
import Synchronization
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

    @Test func duplicateHashInsertKeepsExistingRow() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = DocumentRepository(database: db)
        let idA = "10000000-0000-0000-0000-0000000000a1"
        let idB = "10000000-0000-0000-0000-0000000000a2"
        let original = TestData.document(id: idA, title: "Quantum", fileHash: "same")
        let duplicate = TestData.document(id: idB, title: "Biology", fileHash: "same")
        try await repo.insert(original)

        await #expect(throws: DatabaseError.self) {
            try await repo.insert(duplicate)
        }

        #expect(try await repo.fetch(id: idA) == original)
        #expect(try await repo.fetch(id: idB) == nil)
        #expect(try await repo.fetchAll().count == 1)
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

    @Test func fetchByHash() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = DocumentRepository(database: db)
        let first = TestData.document(id: "10000000-0000-0000-0000-0000000000a1", fileHash: "hash-one")
        let second = TestData.document(id: "10000000-0000-0000-0000-0000000000a2", fileHash: "hash-two")
        try await repo.insert(first)
        try await repo.insert(second)

        #expect(try await repo.fetch(fileHash: "hash-one") == first)
        #expect(try await repo.fetch(fileHash: "hash-two") == second)
        #expect(try await repo.fetch(fileHash: "hash-unknown") == nil)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func deleteCascades() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = DocumentRepository(database: db)
        let fileStore = TestFileStore.make()
        defer { TestFileStore.remove(fileStore) }
        try fileStore.createRootDirectories()

        // FileStore accepts only canonical (uppercase) UUID strings.
        let documentId = UUID().uuidString
        let document = TestData.document(id: documentId, title: "Doomed")
        let folder = try fileStore.createDocumentFolder(documentId: documentId)
        try Data("%PDF-1.4".utf8).write(to: try fileStore.originalFileURL(documentId: documentId, fileType: .pdf))

        let highlightOne = TestData.highlight(documentId: documentId, id: "20000000-0000-0000-0000-0000000000b1")
        let highlightTwo = TestData.highlight(documentId: documentId, id: "20000000-0000-0000-0000-0000000000b2")
        let tag = TestData.tag(name: "exam", id: "30000000-0000-0000-0000-0000000000c1")
        let card = TestData.reviewCard(highlightId: highlightOne.id, id: "40000000-0000-0000-0000-0000000000d1")
        try await db.writer.write { db in
            try document.insert(db)
            try DocumentText(documentId: documentId, unitIndex: 0, startOffset: 0, text: "Some body text")
                .insert(db)
            try highlightOne.insert(db)
            try highlightTwo.insert(db)
            try tag.insert(db)
            try HighlightTag(highlightId: highlightOne.id, tagId: tag.id).insert(db)
            try DocumentTag(documentId: documentId, tagId: tag.id).insert(db)
            try DocumentNote(documentId: documentId, body: "Remember this", updatedAt: TestData.referenceDate)
                .insert(db)
            try card.insert(db)
            try ReviewLogEntry(
                id: "50000000-0000-0000-0000-0000000000e1",
                cardId: card.id,
                rating: 3,
                reviewedAt: TestData.referenceDate,
                sessionKind: .daily,
                fsrsLog: "{}"
            ).insert(db)
            try HighlightEmbedding(
                highlightId: highlightOne.id,
                modelId: "NLEmbedding.sentence.en",
                dimension: 2,
                vector: Data([0, 0, 128, 63, 0, 0, 0, 0]),
                sourceHash: "hash"
            ).insert(db)
        }

        let deleted = try await repo.delete(id: documentId, fileStore: fileStore)

        #expect(deleted == true)
        #expect(try await repo.fetch(id: documentId) == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
        try await db.writer.write { db in
            let highlightIds = [highlightOne.id, highlightTwo.id]
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documentText WHERE documentId = ?", arguments: [documentId]) == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM highlight WHERE documentId = ?", arguments: [documentId]) == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM highlightTag WHERE highlightId IN (?, ?)", arguments: StatementArguments(highlightIds)) == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documentTag WHERE documentId = ?", arguments: [documentId]) == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documentNote WHERE documentId = ?", arguments: [documentId]) == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM reviewCard WHERE highlightId IN (?, ?)", arguments: StatementArguments(highlightIds)) == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM reviewLog WHERE cardId = ?", arguments: [card.id]) == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM highlightEmbedding WHERE highlightId IN (?, ?)", arguments: StatementArguments(highlightIds)) == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tag WHERE id = ?", arguments: [tag.id]) == 1)
            try FTSIntegrity.check(db)
        }

        #expect(try await repo.delete(id: documentId, fileStore: fileStore) == false)
    }

    @Test func metadataUpdate() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = DocumentRepository(database: db)
        let documentId = "10000000-0000-0000-0000-0000000000a1"
        try await repo.insert(TestData.document(id: documentId, title: "Oldtitleword"))

        try await repo.updateMetadata(
            id: documentId,
            title: "  Newtitleword Lecture  ",
            author: " Ada Lovelace ",
            categoryId: BuiltinCategory.paper.id
        )

        let fetched = try #require(try await repo.fetch(id: documentId))
        #expect(fetched.title == "Newtitleword Lecture")
        #expect(fetched.author == "Ada Lovelace")
        #expect(fetched.categoryId == BuiltinCategory.paper.id)

        try await db.writer.write { db in
            let newHits = try Int.fetchAll(db, sql: "SELECT rowid FROM document_fts WHERE document_fts MATCH '\"newtitleword\"'")
            let oldHits = try Int.fetchAll(db, sql: "SELECT rowid FROM document_fts WHERE document_fts MATCH '\"oldtitleword\"'")
            #expect(newHits.count == 1)
            #expect(oldHits.isEmpty)
            try FTSIntegrity.check(db)
        }

        await #expect(throws: DocumentEditError.emptyTitle) {
            try await repo.updateMetadata(id: documentId, title: "   ", author: "", categoryId: BuiltinCategory.paper.id)
        }
        await #expect(throws: RepositoryError.notFound) {
            try await repo.updateMetadata(id: "10000000-0000-0000-0000-0000000000ff", title: "X", author: "", categoryId: BuiltinCategory.paper.id)
        }
    }

    @Test func positionAndOpenUpdates() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = DocumentRepository(database: db)
        let documentId = "10000000-0000-0000-0000-0000000000a1"
        try await repo.insert(TestData.document(id: documentId))

        try await repo.updatePDFPosition(
            id: documentId,
            position: PDFPosition(pageIndex: 3, offsetY: 120.5),
            progress: 0.4
        )
        try await repo.updateTextPosition(id: documentId, offset: 42, progress: 1.7)
        try await repo.markOpened(id: documentId, at: TestData.referenceDate)

        let fetched = try #require(try await repo.fetch(id: documentId))
        #expect(fetched.pdfPosition == PDFPosition(pageIndex: 3, offsetY: 120.5))
        #expect(fetched.textPosition == 42)
        #expect(fetched.progress == 1.0)
        #expect(fetched.lastOpenedAt == TestData.referenceDate)

        try await db.writer.write { db in
            #expect(try String.fetchOne(db, sql: "SELECT typeof(lastOpenedAt) FROM document WHERE id = ?", arguments: [documentId]) == "real")
            try FTSIntegrity.check(db)
        }
    }

    @Test func positionUpdateDoesNotTouchSearchIndex() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = DocumentRepository(database: db)
        let documentId = "10000000-0000-0000-0000-0000000000a1"
        try await repo.insert(TestData.document(id: documentId, title: "Indexed title", author: "Indexed author"))

        let trace = Mutex<[String]>([])
        try await db.writer.write { db in
            db.trace { event in trace.withLock { $0.append(event.description) } }
        }

        try await repo.updatePDFPosition(id: documentId, position: PDFPosition(pageIndex: 1, offsetY: 10), progress: 0.2)
        try await repo.updateTextPosition(id: documentId, offset: 5, progress: 0.3)
        try await repo.markOpened(id: documentId, at: TestData.referenceDate)
        try await repo.updateCover(id: documentId, coverPath: "\(documentId)/cover.png", coverSource: .custom)
        try await repo.updateExtraction(id: documentId, status: .done, version: 1)

        try await db.writer.write { db in db.trace() }

        let statements = trace.withLock { $0 }
        let updates = statements.filter { $0.hasPrefix("UPDATE") }
        #expect(updates.contains { $0.contains("UPDATE \"document\" SET") })
        #expect(!updates.contains { $0.contains("\"title\"") || $0.contains("\"author\"") })
        #expect(!statements.contains { $0.contains("document_fts") })
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func coverAndExtractionUpdates() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = DocumentRepository(database: db)
        let documentId = "10000000-0000-0000-0000-0000000000a1"
        try await repo.insert(TestData.document(id: documentId))

        try await repo.updateCover(id: documentId, coverPath: "\(documentId)/cover.png", coverSource: .custom)
        try await repo.updateExtraction(id: documentId, status: .done, version: 1)

        let fetched = try #require(try await repo.fetch(id: documentId))
        #expect(fetched.coverPath == "\(documentId)/cover.png")
        #expect(fetched.coverSource == .custom)
        #expect(fetched.extractionStatus == .done)
        #expect(fetched.extractionVersion == 1)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func itemsIncludeCountsTagsAndCategory() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = DocumentRepository(database: db)
        let slidesId = "10000000-0000-0000-0000-0000000000a1"
        let paperId = "10000000-0000-0000-0000-0000000000a2"
        let slides = TestData.document(
            id: slidesId,
            title: "Slides",
            categoryId: BuiltinCategory.lectureSlides.id,
            addedAt: Date(timeIntervalSince1970: 1_790_000_200)
        )
        let paper = TestData.document(
            id: paperId,
            title: "Paper",
            categoryId: BuiltinCategory.paper.id,
            addedAt: Date(timeIntervalSince1970: 1_790_000_100)
        )
        let tagBeta = TestData.tag(name: "beta", id: "30000000-0000-0000-0000-0000000000c2")
        let tagAlpha = TestData.tag(name: "alpha", id: "30000000-0000-0000-0000-0000000000c1")
        try await repo.insert(slides)
        try await repo.insert(paper)
        try await db.writer.write { db in
            for index in 0..<3 {
                try TestData.highlight(documentId: slidesId, id: "20000000-0000-0000-0000-00000000000\(index)").insert(db)
            }
            try tagBeta.insert(db)
            try tagAlpha.insert(db)
            try DocumentTag(documentId: paperId, tagId: tagBeta.id).insert(db)
            try DocumentTag(documentId: paperId, tagId: tagAlpha.id).insert(db)
        }

        let items = try await repo.fetchAllItems()

        #expect(items.map(\.document.id) == [slidesId, paperId])
        let slidesItem = try #require(items.first { $0.document.id == slidesId })
        let paperItem = try #require(items.first { $0.document.id == paperId })
        #expect(slidesItem.highlightCount == 3)
        #expect(slidesItem.tagIds == [])
        #expect(slidesItem.categoryName == "Lecture slides")
        #expect(paperItem.highlightCount == 0)
        #expect(paperItem.tagIds == [tagAlpha.id, tagBeta.id])
        #expect(paperItem.categoryName == "Paper")
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func observeItemsEmitsAfterHighlightInsert() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = DocumentRepository(database: db)
        let documentId = "10000000-0000-0000-0000-0000000000a1"
        try await repo.insert(TestData.document(id: documentId))
        var iterator = repo.observeItems().makeAsyncIterator()

        let initial = try await iterator.next()
        #expect(initial?.first?.highlightCount == 0)

        try await db.writer.write { db in
            try TestData.highlight(documentId: documentId).insert(db)
        }

        let updated = try await iterator.next()
        #expect(updated?.first?.highlightCount == 1)
    }

    @Test func categoryChangeRecomputesSuspension() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = DocumentRepository(database: db)
        let categories = CategoryRepository(database: db)
        let documentId = "10000000-0000-0000-0000-0000000000a1"
        try await repo.insert(TestData.document(
            id: documentId, title: "Slides", categoryId: BuiltinCategory.lectureSlides.id
        ))
        let highlight = TestData.highlight(documentId: documentId)
        try await HighlightRepository(database: db).insert(highlight)
        let card = TestData.reviewCard(highlightId: highlight.id)
        try await db.writer.write { db in try card.insert(db) }
        try await db.writer.write { db in _ = try ReviewSuspension.recompute(documentIds: [documentId], db) }
        func cardReason() async throws -> SuspendedReason? {
            try #require(try await ReviewCardRepository(database: db).fetch(id: card.id)).suspendedReason
        }
        #expect(try await cardReason() == nil)

        try await categories.setFrequency(id: BuiltinCategory.notes.id, .off)
        try await repo.updateMetadata(
            id: documentId, title: "Slides", author: "", categoryId: BuiltinCategory.notes.id
        )
        #expect(try await cardReason() == .frequencyOff)

        try await repo.updateMetadata(
            id: documentId, title: "Slides", author: "", categoryId: BuiltinCategory.lectureSlides.id
        )
        #expect(try await cardReason() == nil)

        // Moving back to Notes, then saving with the same category: title updates, card is unchanged.
        try await repo.updateMetadata(
            id: documentId, title: "Slides", author: "", categoryId: BuiltinCategory.notes.id
        )
        try await repo.updateMetadata(
            id: documentId, title: "Renamed", author: "Ada", categoryId: BuiltinCategory.notes.id
        )
        let fetched = try #require(try await repo.fetch(id: documentId))
        #expect(fetched.title == "Renamed")
        #expect(try await cardReason() == .frequencyOff)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }
}
