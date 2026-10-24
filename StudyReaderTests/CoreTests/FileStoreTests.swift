import Foundation
import Testing
@testable import StudyReader

@Suite struct FileStoreTests {
    private static let docId = "6F1C2B7E-3D4A-4B8E-9C1D-2A3B4C5D6E7F"
    private static let highlightId = "9A8B7C6D-5E4F-4A3B-8C2D-1E0F9A8B7C6D"

    @Test func pathsFollowLayout() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        let root = store.rootURL.standardizedFileURL.path(percentEncoded: false)

        #expect(store.databaseURL.lastPathComponent == "StudyReader.sqlite")
        #expect(store.databaseURL.standardizedFileURL.path(percentEncoded: false).hasPrefix(root))

        let original = try store.originalFileURL(documentId: Self.docId, fileExtension: "pdf")
        #expect(original.lastPathComponent == "original.pdf")
        #expect(original.deletingLastPathComponent().lastPathComponent == Self.docId)
        #expect(original.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Documents")

        #expect(try store.coverURL(documentId: Self.docId).lastPathComponent == "cover.png")
        #expect(try store.imagesFolderURL(documentId: Self.docId).lastPathComponent == "images")

        let snapshot = try store.snapshotURL(documentId: Self.docId, highlightId: Self.highlightId)
        #expect(snapshot.lastPathComponent == "\(Self.highlightId).png")
        #expect(snapshot.deletingLastPathComponent().lastPathComponent == "snapshots")

        #expect(original.standardizedFileURL.path(percentEncoded: false).hasPrefix(root))
        #expect(try store.coverURL(documentId: Self.docId).standardizedFileURL.path(percentEncoded: false).hasPrefix(root))
        #expect(snapshot.standardizedFileURL.path(percentEncoded: false).hasPrefix(root))
    }

    @Test func relativePathRoundTrip() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        let original = try store.originalFileURL(documentId: Self.docId, fileExtension: "pdf")

        #expect(store.relativePath(for: original) == "\(Self.docId)/original.pdf")
        let resolved = try #require(store.url(forRelativePath: "\(Self.docId)/original.pdf"))
        #expect(resolved.standardizedFileURL == original.standardizedFileURL)

        let outside = store.rootURL.appending(path: "StudyReader.sqlite", directoryHint: .notDirectory)
        #expect(store.relativePath(for: outside) == nil)
    }

    @Test func rejectsEscapingPaths() {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        let escaping = [
            "../StudyReader.sqlite",
            "A/../../../x",
            "\(Self.docId)/../../StudyReader.sqlite",
            "\(Self.docId)/./original.pdf",
            "/etc/passwd",
            "",
            "\(Self.docId)" + "/",
            "\(Self.docId.lowercased())/original.pdf",
            "not-a-uuid/original.pdf",
        ]
        for path in escaping {
            #expect(store.url(forRelativePath: path) == nil, "\(path) should be rejected")
        }

        #expect(store.url(forRelativePath: "\(Self.docId)/original.pdf") != nil)
        #expect(store.url(forRelativePath: "\(Self.docId)/snapshots/\(Self.highlightId).png") != nil)
    }

    @Test func rejectsNonCanonicalIds() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        try store.createRootDirectories()

        #expect(throws: FileStoreError.invalidDocumentId(Self.docId.lowercased())) {
            try store.documentFolderURL(documentId: Self.docId.lowercased())
        }
        #expect(throws: FileStoreError.invalidDocumentId("..")) {
            try store.coverURL(documentId: "..")
        }
        #expect(throws: FileStoreError.invalidDocumentId("")) {
            try store.imagesFolderURL(documentId: "")
        }
        #expect(throws: FileStoreError.invalidDocumentId(Self.docId.lowercased())) {
            try store.createDocumentFolder(documentId: Self.docId.lowercased())
        }
        #expect(throws: FileStoreError.invalidHighlightId("../../../../evil")) {
            try store.snapshotURL(documentId: Self.docId, highlightId: "../../../../evil")
        }
        #expect(throws: FileStoreError.invalidHighlightId(Self.highlightId.lowercased())) {
            try store.snapshotURL(documentId: Self.docId, highlightId: Self.highlightId.lowercased())
        }
    }

    @Test func rejectsInvalidFileExtensions() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        let invalid = ["", "../x", "PDF", "p d f", "abcdefghijk", "pdf/"]
        for fileExtension in invalid {
            #expect(throws: FileStoreError.invalidFileExtension(fileExtension)) {
                try store.originalFileURL(documentId: Self.docId, fileExtension: fileExtension)
            }
        }

        for fileExtension in ["pdf", "md", "markdown"] {
            let url = try store.originalFileURL(documentId: Self.docId, fileExtension: fileExtension)
            #expect(url.lastPathComponent == "original.\(fileExtension)")
        }
    }

    @Test func createRootDirectoriesIsIdempotent() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        try store.createRootDirectories()
        try store.createRootDirectories()

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: store.rootURL.path(percentEncoded: false),
                                               isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(FileManager.default.fileExists(atPath: store.documentsURL.path(percentEncoded: false),
                                               isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test func deleteDocumentFolderRemovesContents() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        try store.createRootDirectories()
        let folder = try store.createDocumentFolder(documentId: Self.docId)
        let file = try store.originalFileURL(documentId: Self.docId, fileExtension: "pdf")
        try Data("pdf".utf8).write(to: file)
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))

        try store.deleteDocumentFolder(documentId: Self.docId)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))

        try store.deleteDocumentFolder(documentId: Self.docId)
    }

    @Test func rejectsInvalidDocumentIds() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        try store.createRootDirectories()
        let invalidIds = ["", "..", "a/b", "not-a-uuid", Self.docId.lowercased()]

        for id in invalidIds {
            #expect(throws: FileStoreError.invalidDocumentId(id)) {
                try store.createDocumentFolder(documentId: id)
            }
            #expect(throws: FileStoreError.invalidDocumentId(id)) {
                try store.deleteDocumentFolder(documentId: id)
            }
        }
        #expect(FileManager.default.fileExists(atPath: store.documentsURL.path(percentEncoded: false)))
    }

    @Test func documentFolderIdsListsUUIDFolders() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        #expect(try store.documentFolderIds() == [])

        try store.createRootDirectories()
        let laterId = "FFFFFFFF-0000-4000-8000-000000000001"
        let earlierId = "00000000-0000-4000-8000-000000000002"
        try store.createDocumentFolder(documentId: laterId)
        try store.createDocumentFolder(documentId: earlierId)
        try FileManager.default.createDirectory(
            at: store.documentsURL.appending(path: "tmp", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try Data().write(to: store.documentsURL.appending(path: "stray.txt", directoryHint: .notDirectory))

        #expect(try store.documentFolderIds() == [earlierId, laterId].sorted())
    }

    @Test func documentFolderIdsSkipsNonCanonicalNames() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        try store.createRootDirectories()
        try store.createDocumentFolder(documentId: Self.docId)
        try FileManager.default.createDirectory(
            at: store.documentsURL.appending(path: "00000000-0000-4000-8000-00000000000a", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        #expect(try store.documentFolderIds() == [Self.docId])
    }

    @Test func isCanonicalIdRules() {
        #expect(FileStore.isCanonicalId(Self.docId))
        #expect(FileStore.isCanonicalId(UUID().uuidString))
        #expect(!FileStore.isCanonicalId(Self.docId.lowercased()))
        #expect(!FileStore.isCanonicalId("{\(Self.docId)}"))
        #expect(!FileStore.isCanonicalId(""))
        #expect(!FileStore.isCanonicalId("\(Self.docId) "))
    }

    @Test func fileTypeFromSourceExtension() {
        for ext in ["pdf", "PDF", "Pdf"] {
            #expect(FileType(fileExtension: ext) == .pdf)
        }
        for ext in ["md", "MD", "markdown", "Markdown"] {
            #expect(FileType(fileExtension: ext) == .markdown)
        }
        for ext in ["txt", "", "pdf ", "mdx"] {
            #expect(FileType(fileExtension: ext) == nil)
        }
    }

    @Test func uppercaseSourceExtensionMapsToStoredExtension() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }

        let pdfType = try #require(FileType(fileExtension: URL(filePath: "/x/SLIDES.PDF").pathExtension))
        #expect(try store.originalFileURL(documentId: Self.docId, fileType: pdfType).lastPathComponent == "original.pdf")

        let mdType = try #require(FileType(fileExtension: URL(filePath: "/x/Notes.MARKDOWN").pathExtension))
        #expect(try store.originalFileURL(documentId: Self.docId, fileType: mdType).lastPathComponent == "original.md")

        #expect(FileType.pdf.storedFileExtension == "pdf")
        #expect(FileType.markdown.storedFileExtension == "md")
    }

    @Test func relativePathRejectsNonCanonicalFirstComponent() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        let docs = store.documentsURL

        #expect(store.relativePath(for: docs.appending(path: "notes/x.pdf")) == nil)
        #expect(store.relativePath(for: docs.appending(path: "\(Self.docId.lowercased())/original.pdf")) == nil)
        #expect(store.relativePath(for: docs) == nil)
        #expect(store.relativePath(for: docs.appending(path: "\(Self.docId)/original.pdf")) == "\(Self.docId)/original.pdf")

        let snapshot = try store.snapshotURL(documentId: Self.docId, highlightId: Self.highlightId)
        let snapshotPath = try #require(store.relativePath(for: snapshot))
        #expect(store.url(forRelativePath: snapshotPath) != nil)
    }

    @Test func relativePathAlwaysResolves() throws {
        let store = TestFileStore.make()
        defer { TestFileStore.remove(store) }
        let docs = store.documentsURL
        let candidates = [
            docs.appending(path: "notes/x.pdf"),
            docs.appending(path: "\(Self.docId.lowercased())/original.pdf"),
            docs,
            docs.appending(path: "\(Self.docId)/original.pdf"),
            try store.snapshotURL(documentId: Self.docId, highlightId: Self.highlightId),
        ]
        for candidate in candidates {
            if let relative = store.relativePath(for: candidate) {
                #expect(store.url(forRelativePath: relative) != nil, "\(relative) should resolve")
            }
        }
    }
}
