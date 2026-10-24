import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("ExtractionService")
struct ExtractionServiceTests {
    private func makeEnvironment() throws -> AppEnvironment {
        try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
    }

    private func matchCount(_ env: AppEnvironment, query: String) async throws -> Int {
        try await env.database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM documentText_fts WHERE documentText_fts MATCH ?",
                arguments: [query]
            ) ?? 0
        }
    }

    @Test func extractsPDFPages() async throws {
        let env = try makeEnvironment()
        defer { TestFileStore.remove(env.fileStore) }
        let source = try PDFFixtureBuilder.writeTemporary(
            PDFFixtureBuilder.plainMultiPage(pageCount: 3), name: "lecture.pdf"
        )

        let report = await env.importService.importItems(at: [source], interaction: StubInteraction())
        #expect(report.imported.count == 1)
        let id = try #require(report.imported.first?.documentId)
        await env.extractionService.waitUntilIdle()

        let units = try await env.documentTextRepository.fetchUnits(documentId: id)
        #expect(units.map(\.unitIndex) == [0, 1, 2])
        #expect(units.count == 3)
        let len0 = units[0].text.utf16.count
        let len1 = units[1].text.utf16.count
        #expect(units.map(\.startOffset) == [0, len0 + 2, len0 + len1 + 4])

        let document = try #require(await env.documentRepository.fetch(id: id))
        #expect(document.extractionStatus == .done)
        #expect(document.extractionVersion == PDFTextExtractor.version)

        #expect(try await matchCount(env, query: "quick") == 3)
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func extractsMarkdownSections() async throws {
        let env = try makeEnvironment()
        defer { TestFileStore.remove(env.fileStore) }
        let folder = try makeImportTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let markdown = "Intro\n\n# A\n\ntext\n\n## B\n\nmore"
        let source = folder.appending(path: "notes.md", directoryHint: .notDirectory)
        try markdown.write(to: source, atomically: true, encoding: .utf8)

        let report = await env.importService.importItems(at: [source], interaction: StubInteraction())
        #expect(report.imported.count == 1)
        let id = try #require(report.imported.first?.documentId)
        await env.extractionService.waitUntilIdle()

        let expected = MarkdownRenderer.render(
            MarkdownDocumentSource(markdown: markdown, documentId: nil, fileStore: nil)
        ).string
        let units = try await env.documentTextRepository.fetchUnits(documentId: id)
        #expect(units.count == 3)
        #expect(units.map(\.unitIndex) == [0, 1, 2])
        #expect(units.map(\.text).joined() == expected)

        let document = try #require(await env.documentRepository.fetch(id: id))
        #expect(document.extractionStatus == .done)
        #expect(document.extractionVersion == MarkdownRenderer.version)
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func emptyMarkdownHasNoRows() async throws {
        let env = try makeEnvironment()
        defer { TestFileStore.remove(env.fileStore) }
        let folder = try makeImportTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "empty.md", directoryHint: .notDirectory)
        try Data().write(to: source)

        let report = await env.importService.importItems(at: [source], interaction: StubInteraction())
        #expect(report.imported.count == 1)
        let id = try #require(report.imported.first?.documentId)
        await env.extractionService.waitUntilIdle()

        let units = try await env.documentTextRepository.fetchUnits(documentId: id)
        #expect(units.isEmpty)

        let document = try #require(await env.documentRepository.fetch(id: id))
        #expect(document.extractionStatus == .done)
        #expect(document.extractionVersion == MarkdownRenderer.version)
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func missingFileMarksFailed() async throws {
        let env = try makeEnvironment()
        defer { TestFileStore.remove(env.fileStore) }
        // Row whose stored file was never written.
        let document = TestData.document(fileType: .pdf)
        try await env.documentRepository.insert(document)

        await #expect(throws: ExtractionService.ExtractionError.missingFile) {
            try await env.extractionService.extract(documentId: document.id)
        }

        let stored = try #require(await env.documentRepository.fetch(id: document.id))
        #expect(stored.extractionStatus == .failed)
        #expect(try await env.documentTextRepository.fetchUnits(documentId: document.id).isEmpty)
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func reExtractionReplacesRows() async throws {
        let env = try makeEnvironment()
        defer { TestFileStore.remove(env.fileStore) }
        let source = try PDFFixtureBuilder.writeTemporary(
            PDFFixtureBuilder.plainMultiPage(pageCount: 3), name: "lecture.pdf"
        )

        let report = await env.importService.importItems(at: [source], interaction: StubInteraction())
        let id = try #require(report.imported.first?.documentId)
        await env.extractionService.waitUntilIdle()
        let first = try await env.documentTextRepository.fetchUnits(documentId: id)

        try await env.extractionService.extract(documentId: id)
        let second = try await env.documentTextRepository.fetchUnits(documentId: id)

        #expect(first.count == 3)
        #expect(second.count == 3)
        #expect(second.map(\.unitIndex) == [0, 1, 2])
        #expect(second.map(\.text) == first.map(\.text))
        #expect(try await matchCount(env, query: "quick") == 3)
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func deletedDocumentIsSkipped() async throws {
        let env = try makeEnvironment()
        defer { TestFileStore.remove(env.fileStore) }
        // Deleted before the id reaches the queue, so the worker always sees a missing row.
        let document = TestData.document(fileType: .pdf)
        try await env.documentRepository.insert(document)
        _ = try await env.documentRepository.delete(id: document.id, fileStore: env.fileStore)

        await env.extractionService.enqueue(documentId: document.id)
        await env.extractionService.waitUntilIdle()
        try await env.extractionService.extract(documentId: document.id)

        #expect(try await env.documentRepository.fetch(id: document.id) == nil)
        #expect(try await env.documentTextRepository.fetchUnits(documentId: document.id).isEmpty)
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }
}
