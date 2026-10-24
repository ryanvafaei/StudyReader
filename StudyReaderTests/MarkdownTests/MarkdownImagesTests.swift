import Foundation
import Testing
@testable import StudyReader

@Suite struct MarkdownImagesTests {
    @Test func naming() throws {
        let name = try #require(MarkdownImageNaming.storedFileName(forSource: "images/diagram.png"))
        #expect(name.hasSuffix(".png"))
        #expect(name.count == 20)
        let stem = name.dropLast(4)
        #expect(stem.count == 16)
        #expect(stem.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        #expect(MarkdownImageNaming.storedFileName(forSource: "images/diagram.png") == name)

        let upper = try #require(MarkdownImageNaming.storedFileName(forSource: "IMG/A.JPG"))
        #expect(upper.hasSuffix(".jpg"))

        #expect(MarkdownImageNaming.storedFileName(forSource: "https://example.com/remote.png") == nil)
        #expect(MarkdownImageNaming.isRemote("https://example.com/remote.png"))

        #expect(MarkdownImageNaming.storedFileName(forSource: "/abs/x.png") == nil)
        #expect(MarkdownImageNaming.storedFileName(forSource: "#frag") == nil)
        #expect(MarkdownImageNaming.storedFileName(forSource: "noext") == nil)
        #expect(MarkdownImageNaming.storedFileName(forSource: "data:image/png;base64,AAA") == nil)

        let query = try #require(MarkdownImageNaming.storedFileName(forSource: "images/a.png?x=1"))
        #expect(query.hasSuffix(".png"))
    }

    @Test func collectsAndCopies() throws {
        let notes = try MarkdownFixtures.makeFolderWithImages()
        let sourceFolder = notes.deletingLastPathComponent()
        let destinationRoot = FileManager.default.temporaryDirectory
            .appending(path: "MarkdownImagesTests", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let imagesFolder = destinationRoot.appending(path: "images", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: sourceFolder)
            try? FileManager.default.removeItem(at: destinationRoot)
        }

        let body = try MarkdownFixtures.string("all-elements")
        #expect(MarkdownImageCollector.imageSources(in: body) == [
            "images/diagram.png", "images/missing.png", "https://example.com/remote.png",
        ])

        let sources = MarkdownImageCollector.imageSources(in: body)
        let first = MarkdownImageCollector.copyImages(sources: sources, from: sourceFolder, to: imagesFolder)
        #expect(first == MarkdownImageCollector.CopyResult(copied: 1, missing: 1, unreadable: 0, alreadyPresent: 0))

        let storedName = try #require(MarkdownImageNaming.storedFileName(forSource: "images/diagram.png"))
        let copied = imagesFolder.appending(path: storedName)
        let originalBytes = try Data(contentsOf: sourceFolder.appending(path: "images/diagram.png"))
        #expect(try Data(contentsOf: copied) == originalBytes)

        let second = MarkdownImageCollector.copyImages(sources: sources, from: sourceFolder, to: imagesFolder)
        #expect(second == MarkdownImageCollector.CopyResult(copied: 0, missing: 1, unreadable: 0, alreadyPresent: 1))
    }

    @Test func permissionErrorIsUnreadable() throws {
        let notes = try MarkdownFixtures.makeFolderWithImages()
        let sourceFolder = notes.deletingLastPathComponent()
        let destinationRoot = FileManager.default.temporaryDirectory
            .appending(path: "MarkdownImagesTests", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let imagesFolder = destinationRoot.appending(path: "images", directoryHint: .isDirectory)
        let diagram = sourceFolder.appending(path: "images/diagram.png")
        defer {
            try? FileManager.default.removeItem(at: sourceFolder)
            try? FileManager.default.removeItem(at: destinationRoot)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: diagram.path(percentEncoded: false))
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: diagram.path(percentEncoded: false))
        }

        let result = MarkdownImageCollector.copyImages(
            sources: ["images/diagram.png", "images/missing.png"],
            from: sourceFolder,
            to: imagesFolder
        )
        #expect(result.unreadable == 1)
        #expect(result.missing == 1)
    }

    @Test func fileStoreBuilderValidates() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        let documentId = UUID().uuidString
        let url = try store.markdownImageURL(documentId: documentId, storedFileName: "0123456789abcdef.png")
        #expect(url.path(percentEncoded: false).contains("/Documents/\(documentId)/images/"))
        #expect(url.lastPathComponent == "0123456789abcdef.png")

        for invalid in ["../x.png", "ABCDEF0123456789.png", "short.png"] {
            #expect(throws: FileStoreError.invalidFileExtension(invalid)) {
                try store.markdownImageURL(documentId: documentId, storedFileName: invalid)
            }
        }
    }
}
