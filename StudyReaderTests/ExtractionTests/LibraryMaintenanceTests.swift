import Foundation
import Testing
@testable import StudyReader

@Suite("LibraryMaintenance")
struct LibraryMaintenanceTests {
    /// `<root>/Documents/<name>` for the store's documents folder.
    private func documentFolder(_ store: FileStore, _ name: String) -> URL {
        store.rootURL
            .appending(path: "Documents", directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .isDirectory)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test func removesOrphanFolders() async throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        try store.createRootDirectories()
        let database = try AppDatabase.makeShared(fileStore: store)
        let maintenance = LibraryMaintenance(database: database, fileStore: store)

        let kept = TestData.document()
        try await DocumentRepository(database: database).insert(kept)
        try store.createDocumentFolder(documentId: kept.id)
        let orphanId = UUID().uuidString
        try store.createDocumentFolder(documentId: orphanId)
        let keepMe = documentFolder(store, "keep-me")
        try FileManager.default.createDirectory(at: keepMe, withIntermediateDirectories: true)

        let removed = try maintenance.removeOrphanFolders()

        #expect(removed == [orphanId])
        #expect(!exists(documentFolder(store, orphanId)))
        #expect(exists(documentFolder(store, kept.id)))
        #expect(exists(keepMe))
        try await database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func findsPendingAndOutdated() async throws {
        let database = try AppDatabase.makeInMemory()
        let repository = DocumentRepository(database: database)
        let maintenance = LibraryMaintenance(database: database, fileStore: TestFileStore.make())

        let pendingPDF = TestData.document(fileType: .pdf)                 // pending (default)
        var currentPDF = TestData.document(fileType: .pdf)
        currentPDF.extractionStatus = .done
        currentPDF.extractionVersion = PDFTextExtractor.version
        var outdatedPDF = TestData.document(fileType: .pdf)
        outdatedPDF.extractionStatus = .done
        outdatedPDF.extractionVersion = 0
        var failedMarkdown = TestData.document(fileType: .markdown)
        failedMarkdown.extractionStatus = .failed
        var outdatedMarkdown = TestData.document(fileType: .markdown)
        outdatedMarkdown.extractionStatus = .done
        outdatedMarkdown.extractionVersion = 0

        for document in [pendingPDF, currentPDF, outdatedPDF, failedMarkdown, outdatedMarkdown] {
            try await repository.insert(document)
        }

        let ids = try await maintenance.documentIdsNeedingExtraction()

        #expect(ids == [pendingPDF.id, outdatedPDF.id, outdatedMarkdown.id].sorted())
        #expect(!ids.contains(currentPDF.id))
        #expect(!ids.contains(failedMarkdown.id))
        try await database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func launchMakeSweepsOrphans() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        try store.createRootDirectories()
        let orphanId = UUID().uuidString
        try store.createDocumentFolder(documentId: orphanId)
        #expect(exists(documentFolder(store, orphanId)))

        _ = try AppEnvironment.make(fileStore: store)

        #expect(!exists(documentFolder(store, orphanId)))
    }

    @Test func backfillCreatesPassiveCardsOnce() async throws {
        let env = try AppEnvironment.inMemory()
        let database = env.database
        let settings = TestSettings.make()
        defer { TestSettings.remove(settings) }
        let now = TestData.referenceDate
        let categories = CategoryRepository(database: database)
        try await categories.setAutoCreateCards(id: BuiltinCategory.notes.id, false)

        let lectures = TestData.document(categoryId: BuiltinCategory.lectureSlides.id)
        let notes = TestData.document(categoryId: BuiltinCategory.notes.id)
        try await DocumentRepository(database: database).insert(lectures)
        try await DocumentRepository(database: database).insert(notes)
        let highlights = HighlightRepository(database: database)
        let withQA = TestData.highlight(documentId: lectures.id, createdAt: now)
        let plain = TestData.highlight(documentId: lectures.id, createdAt: now.addingTimeInterval(-500))
        let offCategory = TestData.highlight(documentId: notes.id, createdAt: now)
        for highlight in [withQA, plain, offCategory] {
            try await highlights.insert(highlight)
        }
        let qa = try ReviewCardFactory.mastery(
            highlightId: withQA.id, cardType: .qa, clozeRanges: nil,
            question: "Q", answer: "A", now: now
        )
        try await database.writer.write { db in try qa.insert(db) }

        let maintenance = LibraryMaintenance(database: database, fileStore: env.fileStore)
        let inserted = try await maintenance.backfillPassiveCardsOnce(
            cards: env.reviewCardRepository, settings: settings
        )

        #expect(inserted == 1)
        let plainCards = try await env.reviewCardRepository.cards(forHighlight: plain.id)
        #expect(plainCards.map(\.cardType) == [.passive])
        #expect(plainCards.first?.dueAt == plain.createdAt)
        #expect(try await env.reviewCardRepository.cards(forHighlight: offCategory.id).isEmpty)
        #expect(try await env.reviewCardRepository.cards(forHighlight: withQA.id).map(\.cardType) == [.qa])
        #expect(settings.passiveCardBackfillDone)

        // The flag short-circuits: a highlight added after the first run gets no card from a second call.
        let later = TestData.highlight(documentId: lectures.id, createdAt: now)
        try await highlights.insert(later)
        let second = try await maintenance.backfillPassiveCardsOnce(
            cards: env.reviewCardRepository, settings: settings
        )
        #expect(second == 0)
        #expect(try await env.reviewCardRepository.cards(forHighlight: later.id).isEmpty)
        try await database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func backfillHonoursOffCategories() async throws {
        let env = try AppEnvironment.inMemory()
        let database = env.database
        let settings = TestSettings.make()
        defer { TestSettings.remove(settings) }
        let document = TestData.document(categoryId: BuiltinCategory.lectureSlides.id)
        try await DocumentRepository(database: database).insert(document)
        let highlight = TestData.highlight(documentId: document.id)
        try await HighlightRepository(database: database).insert(highlight)
        try await CategoryRepository(database: database)
            .setFrequency(id: BuiltinCategory.lectureSlides.id, .off)

        let inserted = try await LibraryMaintenance(database: database, fileStore: env.fileStore)
            .backfillPassiveCardsOnce(cards: env.reviewCardRepository, settings: settings)

        #expect(inserted == 0)
        #expect(try await env.reviewCardRepository.cards(forHighlight: highlight.id).isEmpty)
        #expect(settings.passiveCardBackfillDone)
        try await database.writer.write { db in try FTSIntegrity.check(db) }
    }
}
