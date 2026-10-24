import Foundation
import Testing
@testable import StudyReader

private func setPermissions(_ mode: Int, atPath path: String) {
    try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
}

@Suite("MarkdownImport")
struct MarkdownImportTests {
    @Test
    func copiesRelativeImages() async throws {
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }
        let notes = try MarkdownFixtures.makeFolderWithImages()
        defer { try? FileManager.default.removeItem(at: notes.deletingLastPathComponent()) }

        let report = await harness.service.importItems(at: [notes], interaction: StubInteraction())

        #expect(report.imported.count == 1)
        let documentId = try #require(report.imported.first).documentId
        let fileStore = harness.env.fileStore

        let diagram = try fileStore.markdownImageURL(
            documentId: documentId,
            storedFileName: try #require(MarkdownImageNaming.storedFileName(forSource: "images/diagram.png"))
        )
        #expect(FileManager.default.fileExists(atPath: diagram.path(percentEncoded: false)))

        let missing = try fileStore.markdownImageURL(
            documentId: documentId,
            storedFileName: try #require(MarkdownImageNaming.storedFileName(forSource: "images/missing.png"))
        )
        #expect(!FileManager.default.fileExists(atPath: missing.path(percentEncoded: false)))

        if let remoteName = MarkdownImageNaming.storedFileName(forSource: "https://example.com/remote.png") {
            let remote = try fileStore.markdownImageURL(documentId: documentId, storedFileName: remoteName)
            #expect(!FileManager.default.fileExists(atPath: remote.path(percentEncoded: false)))
        }

        let imagesFolder = try fileStore.imagesFolderURL(documentId: documentId)
        let copied = try FileManager.default.contentsOfDirectory(atPath: imagesFolder.path(percentEncoded: false))
        #expect(copied == [diagram.lastPathComponent])

        #expect(report.missingImageCount == 1)
        #expect(report.unreadableImageCount == 0)

        try await harness.checkFTS()
    }

    @Test
    func frontMatter() async throws {
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }
        let folder = try makeImportTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "front-matter.md", directoryHint: .notDirectory)
        try FileManager.default.copyItem(at: MarkdownFixtures.url("front-matter"), to: source)

        let report = await harness.service.importItems(at: [source], interaction: StubInteraction())

        let row = try await harness.document(id: try #require(report.imported.first).documentId)
        #expect(row.title == "Gradient Descent Notes")
        #expect(row.author == "Ada Lovelace")
        #expect(report.imported.first?.title == "Gradient Descent Notes")

        try await harness.checkFTS()
    }

    @Test
    func folderAccessApprovedCopiesImages() async throws {
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }
        let notes = try MarkdownFixtures.makeFolderWithImages()
        let folder = notes.deletingLastPathComponent()
        let imagePath = folder.appending(path: "images/diagram.png", directoryHint: .notDirectory).path(percentEncoded: false)
        setPermissions(0o000, atPath: imagePath)
        defer {
            setPermissions(0o644, atPath: imagePath)
            try? FileManager.default.removeItem(at: folder)
        }

        let interaction = StubInteraction(folderAnswer: { given in
            setPermissions(0o644, atPath: imagePath)
            return given
        })
        let report = await harness.service.importItems(at: [notes], interaction: interaction)

        #expect(report.imported.count == 1)
        let calls = await interaction.log.folderAccessCalls
        #expect(calls == [.folderAccess(folder: folder.standardizedFileURL, markdownFileName: "notes.md")])

        let documentId = try #require(report.imported.first).documentId
        let diagram = try harness.env.fileStore.markdownImageURL(
            documentId: documentId,
            storedFileName: try #require(MarkdownImageNaming.storedFileName(forSource: "images/diagram.png"))
        )
        #expect(FileManager.default.fileExists(atPath: diagram.path(percentEncoded: false)))
        #expect(report.unreadableImageCount == 0)
        #expect(!report.summary.contains("image"))

        try await harness.checkFTS()
    }

    @Test
    func folderAccessCancelledLeavesPlaceholders() async throws {
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }
        let notes = try MarkdownFixtures.makeFolderWithImages()
        let folder = notes.deletingLastPathComponent()
        let imagePath = folder.appending(path: "images/diagram.png", directoryHint: .notDirectory).path(percentEncoded: false)
        setPermissions(0o000, atPath: imagePath)
        defer {
            setPermissions(0o644, atPath: imagePath)
            try? FileManager.default.removeItem(at: folder)
        }

        let interaction = StubInteraction(folderAnswer: { _ in nil })
        let report = await harness.service.importItems(at: [notes], interaction: interaction)

        #expect(report.imported.count == 1)
        #expect(await interaction.log.folderAccessCalls.count == 1)
        let documentId = try #require(report.imported.first).documentId
        let diagram = try harness.env.fileStore.markdownImageURL(
            documentId: documentId,
            storedFileName: try #require(MarkdownImageNaming.storedFileName(forSource: "images/diagram.png"))
        )
        #expect(!FileManager.default.fileExists(atPath: diagram.path(percentEncoded: false)))
        #expect(report.unreadableImageCount == 1)
        #expect(report.summary.hasSuffix("1 image couldn't be read and shows as a placeholder."))

        try await harness.checkFTS()
    }

    @Test
    func folderAccessAskedOncePerFolderPerBatch() async throws {
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }
        let notes = try MarkdownFixtures.makeFolderWithImages()
        let folder = notes.deletingLastPathComponent()
        let imagePath = folder.appending(path: "images/diagram.png", directoryHint: .notDirectory).path(percentEncoded: false)
        setPermissions(0o000, atPath: imagePath)
        defer {
            setPermissions(0o644, atPath: imagePath)
            try? FileManager.default.removeItem(at: folder)
        }

        let body = try String(contentsOf: notes, encoding: .utf8)
        let second = folder.appending(path: "second.md", directoryHint: .notDirectory)
        try (body + "\n\nSecond file.\n").write(to: second, atomically: true, encoding: .utf8)
        let third = folder.appending(path: "third.md", directoryHint: .notDirectory)
        try (body + "\n\nThird file.\n").write(to: third, atomically: true, encoding: .utf8)

        let interaction = StubInteraction(folderAnswer: { _ in nil })
        let firstReport = await harness.service.importItems(at: [notes, second], interaction: interaction)
        #expect(firstReport.imported.count == 2)
        #expect(firstReport.unreadableImageCount == 2)
        #expect(await interaction.log.folderAccessCalls.count == 1)

        let secondReport = await harness.service.importItems(at: [third], interaction: interaction)
        #expect(secondReport.imported.count == 1)
        #expect(await interaction.log.folderAccessCalls.count == 2)

        try await harness.checkFTS()
    }

    @Test
    func noPromptWhenImagesReadable() async throws {
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }
        let notes = try MarkdownFixtures.makeFolderWithImages()
        defer { try? FileManager.default.removeItem(at: notes.deletingLastPathComponent()) }

        let interaction = StubInteraction(folderAnswer: { given in given })
        let report = await harness.service.importItems(at: [notes], interaction: interaction)

        #expect(report.imported.count == 1)
        #expect(await interaction.log.folderAccessCalls.isEmpty)
        #expect(report.unreadableImageCount == 0)

        try await harness.checkFTS()
    }

    @Test
    func noBookmarkStored() async throws {
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }
        let notes = try MarkdownFixtures.makeFolderWithImages()
        let folder = notes.deletingLastPathComponent()
        let imagePath = folder.appending(path: "images/diagram.png", directoryHint: .notDirectory).path(percentEncoded: false)
        setPermissions(0o000, atPath: imagePath)
        defer {
            setPermissions(0o644, atPath: imagePath)
            try? FileManager.default.removeItem(at: folder)
        }

        let suiteName = try #require(harness.settings.suiteName)
        let keysBefore = Set(harness.settings.defaults.persistentDomain(forName: suiteName)?.keys.map { $0 } ?? [])

        let interaction = StubInteraction(folderAnswer: { given in
            setPermissions(0o644, atPath: imagePath)
            return given
        })
        let report = await harness.service.importItems(at: [notes], interaction: interaction)
        #expect(report.imported.count == 1)
        #expect(await interaction.log.folderAccessCalls.count == 1)

        let row = try await harness.document(id: try #require(report.imported.first).documentId)
        if let bookmark = row.originalBookmark {
            var isStale = false
            let resolved = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            #expect(resolved.resolvingSymlinksInPath().path(percentEncoded: false)
                    == notes.resolvingSymlinksInPath().path(percentEncoded: false))
        }

        let keysAfter = Set(harness.settings.defaults.persistentDomain(forName: suiteName)?.keys.map { $0 } ?? [])
        #expect(keysAfter == keysBefore)

        let documentFolder = try harness.env.fileStore.documentFolderURL(documentId: row.id)
        let entries = try FileManager.default.contentsOfDirectory(atPath: documentFolder.path(percentEncoded: false))
        #expect(Set(entries) == ["original.md", "images"])

        try await harness.checkFTS()
    }
}
