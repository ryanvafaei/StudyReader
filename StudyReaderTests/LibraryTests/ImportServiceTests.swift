import Foundation
import PDFKit
import Testing
@testable import StudyReader

// MARK: - Shared stubs and helpers (also used by MarkdownImportTests)

actor InteractionLog {
    enum Call: Equatable, Sendable {
        case largeFile(name: String)
        case password(name: String)
        case folderAccess(folder: URL, markdownFileName: String)
    }

    private(set) var calls: [Call] = []

    func record(_ call: Call) {
        calls.append(call)
    }

    var passwordCount: Int {
        calls.filter { if case .password = $0 { true } else { false } }.count
    }

    var folderAccessCalls: [Call] {
        calls.filter { if case .folderAccess = $0 { true } else { false } }
    }
}

struct StubInteraction: ImportInteraction {
    var allowLarge = true
    var password: String?
    /// Called by requestFolderAccess; returns the URL to approve or nil to cancel. Default: cancel.
    var folderAnswer: @Sendable (URL) -> URL? = { _ in nil }
    let log = InteractionLog()

    func confirmLargeFile(named name: String, byteCount: Int64) async -> Bool {
        await log.record(.largeFile(name: name))
        return allowLarge
    }

    func password(forFileNamed name: String) async -> String? {
        await log.record(.password(name: name))
        return password
    }

    func requestFolderAccess(for folder: URL, markdownFileName: String) async -> URL? {
        await log.record(.folderAccess(folder: folder, markdownFileName: markdownFileName))
        return folderAnswer(folder)
    }
}

actor RecordingQueue: ExtractionQueue {
    private(set) var ids: [String] = []

    func enqueue(documentId: String) {
        ids.append(documentId)
    }
}

/// Everything an import test needs: an in-memory library, a settings suite, a queue and the service.
struct ImportHarness {
    let env: AppEnvironment
    let settings: SettingsStore
    let queue: RecordingQueue
    let service: ImportService

    static func make(largeFileThreshold: Int64 = ImportService.defaultLargeFileThreshold) throws -> ImportHarness {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        let settings = TestSettings.make()
        let queue = RecordingQueue()
        let covers = CoverService(fileStore: env.fileStore, documents: env.documentRepository)
        let service = ImportService(
            fileStore: env.fileStore,
            documents: env.documentRepository,
            categories: env.categoryRepository,
            covers: covers,
            settings: settings,
            now: env.now,
            extractionQueue: queue,
            largeFileThreshold: largeFileThreshold
        )
        return ImportHarness(env: env, settings: settings, queue: queue, service: service)
    }

    func cleanup() {
        TestFileStore.remove(env.fileStore)
        TestSettings.remove(settings)
    }

    func checkFTS() async throws {
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    func document(id: String) async throws -> LibraryDocument {
        try #require(await env.documentRepository.fetch(id: id))
    }

    func storedURL(of document: LibraryDocument) throws -> URL {
        try #require(env.fileStore.url(forRelativePath: document.storedPath))
    }
}

func makeImportTemporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory
        .appending(path: "ImportTests", directoryHint: .isDirectory)
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

// MARK: - Tests

@Suite("ImportService")
struct ImportServiceTests {
    @Test
    func importsPDFAndMarkdown() async throws {
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }
        let folder = try makeImportTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let pdfSource = try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.plainMultiPage(), name: "lecture.pdf")
        let markdownSource = folder.appending(path: "front-matter.md", directoryHint: .notDirectory)
        try FileManager.default.copyItem(at: MarkdownFixtures.url("front-matter"), to: markdownSource)

        let report = await harness.service.importItems(at: [pdfSource, markdownSource], interaction: StubInteraction())

        #expect(report.imported.count == 2)
        #expect(report.duplicates.isEmpty)
        #expect(report.failures.isEmpty)
        #expect(report.unsupported.isEmpty)

        let sources = [pdfSource, markdownSource]
        for (imported, source) in zip(report.imported, sources) {
            let row = try await harness.document(id: imported.documentId)
            let stored = try harness.storedURL(of: row)
            #expect(FileManager.default.fileExists(atPath: stored.path(percentEncoded: false)))
            #expect(try Hashing.sha256Hex(ofFileAt: stored) == Hashing.sha256Hex(ofFileAt: source))
            #expect(row.fileHash == (try Hashing.sha256Hex(ofFileAt: source)))
            #expect(row.categoryId == BuiltinCategory.lectureSlides.id)
            #expect(row.addedAt == TestData.referenceDate)
        }

        let pdfRow = try await harness.document(id: report.imported[0].documentId)
        #expect(pdfRow.fileType == .pdf)
        #expect(pdfRow.pageCount == 5)
        #expect(pdfRow.coverPath == "\(pdfRow.id)/cover.png")
        let coverURL = try harness.env.fileStore.coverURL(documentId: pdfRow.id)
        #expect(FileManager.default.fileExists(atPath: coverURL.path(percentEncoded: false)))

        let markdownRow = try await harness.document(id: report.imported[1].documentId)
        #expect(markdownRow.fileType == .markdown)
        #expect(markdownRow.coverPath == nil)

        let queued = await harness.queue.ids
        #expect(queued == report.imported.map(\.documentId))
        #expect(Set(queued) == [pdfRow.id, markdownRow.id])

        try await harness.checkFTS()
    }

    @Test
    func deduplicatesByHash() async throws {
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }
        let data = PDFFixtureBuilder.plainMultiPage()
        let first = try PDFFixtureBuilder.writeTemporary(data, name: "original.pdf")
        let second = try PDFFixtureBuilder.writeTemporary(data, name: "copy.PDF")

        let firstReport = await harness.service.importItems(at: [first], interaction: StubInteraction())
        #expect(firstReport.imported.count == 1)
        let title = try #require(firstReport.imported.first?.title)

        let secondReport = await harness.service.importItems(at: [second], interaction: StubInteraction())
        #expect(secondReport.imported.isEmpty)
        #expect(secondReport.duplicates == [title])
        #expect(secondReport.summary.contains("Already in library: "))
        #expect(secondReport.summary.contains("Already in library: \(title)"))

        let rows = try await harness.env.documentRepository.fetchAll()
        #expect(rows.count == 1)
        #expect(try harness.env.fileStore.documentFolderIds().count == 1)
        #expect(await harness.queue.ids.count == 1)

        try await harness.checkFTS()
    }

    @Test
    func reportsUnsupportedAndDamaged() async throws {
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }
        let folder = try makeImportTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let text = folder.appending(path: "a.txt", directoryHint: .notDirectory)
        try Data("plain".utf8).write(to: text)
        let image = folder.appending(path: "b.png", directoryHint: .notDirectory)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: image)
        let broken = try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.damaged(), name: "broken.pdf")

        let report = await harness.service.importItems(at: [text, image, broken], interaction: StubInteraction())

        #expect(report.imported.isEmpty)
        #expect(try await harness.env.documentRepository.fetchAll().isEmpty)
        #expect(report.unsupported == ["a.txt", "b.png"])
        #expect(report.failures == [ImportFailure(fileName: "broken.pdf", reason: .damaged)])
        #expect(report.summary == "Imported 0, skipped 2 (unsupported type)\nCouldn't open broken.pdf")
        #expect(try harness.env.fileStore.documentFolderIds().isEmpty)
        #expect(await harness.queue.ids.isEmpty)

        try await harness.checkFTS()
    }

    @Test
    func uppercaseExtensionImports() async throws {
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }
        let source = try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.plainMultiPage(), name: "SLIDES.PDF")

        let report = await harness.service.importItems(at: [source], interaction: StubInteraction())

        #expect(report.imported.count == 1)
        let row = try await harness.document(id: try #require(report.imported.first).documentId)
        #expect(row.storedPath.hasSuffix("original.pdf"))
        #expect(row.originalFilename == "SLIDES.PDF")
        #expect(row.fileType == .pdf)
        let stored = try harness.storedURL(of: row)
        #expect(FileManager.default.fileExists(atPath: stored.path(percentEncoded: false)))

        try await harness.checkFTS()
    }

    @Test
    func encryptedPDFWithPassword() async throws {
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }
        let source = try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.encrypted(password: "secret"), name: "locked.pdf")

        // Wrong password: asked once, nothing stored.
        let wrong = StubInteraction(password: "nope")
        let wrongReport = await harness.service.importItems(at: [source], interaction: wrong)
        #expect(wrongReport.imported.isEmpty)
        #expect(wrongReport.failures == [ImportFailure(fileName: "locked.pdf", reason: .wrongPassword)])
        #expect(await wrong.log.passwordCount == 1)
        #expect(try await harness.env.documentRepository.fetchAll().isEmpty)
        #expect(try harness.env.fileStore.documentFolderIds().isEmpty)

        // Cancelled prompt.
        let cancelled = StubInteraction(password: nil)
        let cancelledReport = await harness.service.importItems(at: [source], interaction: cancelled)
        #expect(cancelledReport.imported.isEmpty)
        #expect(cancelledReport.failures == [ImportFailure(fileName: "locked.pdf", reason: .passwordCancelled)])
        #expect(await cancelled.log.passwordCount == 1)
        #expect(try harness.env.fileStore.documentFolderIds().isEmpty)

        // Right password: imported, the stored copy opens without a password.
        let right = StubInteraction(password: "secret")
        let rightReport = await harness.service.importItems(at: [source], interaction: right)
        #expect(rightReport.imported.count == 1)
        #expect(rightReport.failures.isEmpty)
        #expect(await right.log.passwordCount == 1)
        let row = try await harness.document(id: try #require(rightReport.imported.first).documentId)
        let stored = try harness.storedURL(of: row)
        let opened = try #require(PDFDocument(url: stored))
        #expect(opened.isLocked == false)
        #expect(row.fileHash == (try Hashing.sha256Hex(ofFileAt: source)))
        #expect(row.pageCount != nil)

        try await harness.checkFTS()
    }

    @Test
    func largeFileNeedsConfirmation() async throws {
        let harness = try ImportHarness.make(largeFileThreshold: 10)
        defer { harness.cleanup() }
        let source = try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.plainMultiPage(), name: "big.pdf")

        let declining = StubInteraction(allowLarge: false)
        let declined = await harness.service.importItems(at: [source], interaction: declining)
        #expect(declined.imported.isEmpty)
        #expect(declined.failures == [ImportFailure(fileName: "big.pdf", reason: .declinedLargeFile)])
        #expect(await declining.log.calls == [.largeFile(name: "big.pdf")])
        #expect(try await harness.env.documentRepository.fetchAll().isEmpty)
        #expect(try harness.env.fileStore.documentFolderIds().isEmpty)

        let allowing = StubInteraction(allowLarge: true)
        let allowed = await harness.service.importItems(at: [source], interaction: allowing)
        #expect(allowed.imported.count == 1)
        #expect(allowed.failures.isEmpty)
        #expect(await allowing.log.calls == [.largeFile(name: "big.pdf")])
        #expect(try await harness.env.documentRepository.fetchAll().count == 1)

        try await harness.checkFTS()
    }

    @Test
    func folderDepthAndOrdering() async throws {
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }
        let temporary = try makeImportTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: temporary) }

        let root = temporary.appending(path: "root", directoryHint: .isDirectory)
        let deep = root.appending(path: "1/2/3", directoryHint: .isDirectory)
        let tooDeep = deep.appending(path: "4", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tooDeep, withIntermediateDirectories: true)
        try PDFFixtureBuilder.plainMultiPage().write(to: root.appending(path: "a.pdf", directoryHint: .notDirectory))
        try Data("# B\n".utf8).write(to: deep.appending(path: "b.md", directoryHint: .notDirectory))
        try Data("# C\n".utf8).write(to: tooDeep.appending(path: "c.md", directoryHint: .notDirectory))
        try Data("text".utf8).write(to: root.appending(path: "notes.txt", directoryHint: .notDirectory))
        try PDFFixtureBuilder.plainMultiPage(pageCount: 2)
            .write(to: root.appending(path: ".hidden.pdf", directoryHint: .notDirectory))

        let report = await harness.service.importItems(at: [root], interaction: StubInteraction())

        #expect(report.unsupported.isEmpty)
        #expect(report.failures.isEmpty)
        #expect(report.duplicates.isEmpty)
        #expect(report.imported.count == 2)
        var names: [String] = []
        for imported in report.imported {
            names.append(try await harness.document(id: imported.documentId).originalFilename)
        }
        // Files of a folder are imported sorted by path: "root/1/2/3/b.md" comes before "root/a.pdf".
        #expect(names == ["b.md", "a.pdf"])

        try await harness.checkFTS()
    }

    @Test
    func usesDefaultCategorySetting() async throws {
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }

        harness.settings.defaultCategoryId = BuiltinCategory.paper.id
        let first = try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.plainMultiPage(pageCount: 2), name: "one.pdf")
        let firstReport = await harness.service.importItems(at: [first], interaction: StubInteraction())
        let firstRow = try await harness.document(id: try #require(firstReport.imported.first).documentId)
        #expect(firstRow.categoryId == BuiltinCategory.paper.id)

        // A deleted category falls back to Lecture slides.
        let temporary = try await harness.env.categoryRepository.create(name: "Temporary")
        harness.settings.defaultCategoryId = temporary.id
        _ = try await harness.env.categoryRepository.delete(id: temporary.id)
        let second = try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.plainMultiPage(pageCount: 3), name: "two.pdf")
        let secondReport = await harness.service.importItems(at: [second], interaction: StubInteraction())
        let secondRow = try await harness.document(id: try #require(secondReport.imported.first).documentId)
        #expect(secondRow.categoryId == BuiltinCategory.lectureSlides.id)

        // An unknown id does too.
        harness.settings.defaultCategoryId = "does-not-exist"
        let third = try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.plainMultiPage(pageCount: 4), name: "three.pdf")
        let thirdReport = await harness.service.importItems(at: [third], interaction: StubInteraction())
        let thirdRow = try await harness.document(id: try #require(thirdReport.imported.first).documentId)
        #expect(thirdRow.categoryId == BuiltinCategory.lectureSlides.id)

        try await harness.checkFTS()
    }

    @Test
    func summaryFormats() async throws {
        let empty = ImportReport()
        #expect(empty.summary == "")

        var report = ImportReport()
        report.imported = [ImportedDocument(documentId: "1", title: "A"), ImportedDocument(documentId: "2", title: "B")]
        report.unsupported = ["a.txt"]
        report.duplicates = ["Existing One", "Existing Two"]
        report.failures = [
            ImportFailure(fileName: "d.pdf", reason: .damaged),
            ImportFailure(fileName: "w.pdf", reason: .wrongPassword),
            ImportFailure(fileName: "p.pdf", reason: .passwordCancelled),
            ImportFailure(fileName: "big.pdf", reason: .declinedLargeFile),
            ImportFailure(fileName: "x.md", reason: .copyFailed),
        ]
        report.missingImageCount = 3
        report.unreadableImageCount = 1
        #expect(report.summary == """
            Imported 2, skipped 1 (unsupported type)
            Already in library: Existing One
            Already in library: Existing Two
            Couldn't open d.pdf
            Wrong password for w.pdf
            Skipped p.pdf (password required)
            Skipped big.pdf (larger than 500 MB)
            Couldn't import x.md
            1 image couldn't be read and shows as a placeholder.
            """)

        report.unreadableImageCount = 4
        #expect(report.summary.hasSuffix("4 images couldn't be read and show as placeholders."))

        var onlyImported = ImportReport()
        onlyImported.imported = [ImportedDocument(documentId: "1", title: "A")]
        #expect(onlyImported.summary == "Imported 1")

        var onlyDuplicate = ImportReport()
        onlyDuplicate.duplicates = ["Existing"]
        #expect(onlyDuplicate.summary == "Already in library: Existing")

        // This test writes no rows; the integrity check still has to hold on a fresh library.
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }
        try await harness.checkFTS()
    }
}
