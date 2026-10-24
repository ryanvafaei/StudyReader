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
}
