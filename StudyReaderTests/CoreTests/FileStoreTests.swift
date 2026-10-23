import Foundation
import Testing
@testable import StudyReader

@Suite struct FileStoreTests {
    private static let docId = "6F1C2B7E-3D4A-4B8E-9C1D-2A3B4C5D6E7F"
    private static let highlightId = "9A8B7C6D-5E4F-4A3B-8C2D-1E0F9A8B7C6D"

    @Test func pathsFollowLayout() {
        let store = TestFileStore.make()
        let root = store.rootURL.standardizedFileURL.path(percentEncoded: false)

        #expect(store.databaseURL.lastPathComponent == "StudyReader.sqlite")
        #expect(store.databaseURL.standardizedFileURL.path(percentEncoded: false).hasPrefix(root))

        let original = store.originalFileURL(documentId: Self.docId, fileExtension: "pdf")
        #expect(original.lastPathComponent == "original.pdf")
        #expect(original.deletingLastPathComponent().lastPathComponent == Self.docId)
        #expect(original.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Documents")

        #expect(store.coverURL(documentId: Self.docId).lastPathComponent == "cover.png")
        #expect(store.imagesFolderURL(documentId: Self.docId).lastPathComponent == "images")

        let snapshot = store.snapshotURL(documentId: Self.docId, highlightId: Self.highlightId)
        #expect(snapshot.lastPathComponent == "\(Self.highlightId).png")
        #expect(snapshot.deletingLastPathComponent().lastPathComponent == "snapshots")

        #expect(original.standardizedFileURL.path(percentEncoded: false).hasPrefix(root))
        #expect(store.coverURL(documentId: Self.docId).standardizedFileURL.path(percentEncoded: false).hasPrefix(root))
        #expect(snapshot.standardizedFileURL.path(percentEncoded: false).hasPrefix(root))
    }

    @Test func relativePathRoundTrip() {
        let store = TestFileStore.make()
        let original = store.originalFileURL(documentId: Self.docId, fileExtension: "pdf")

        #expect(store.relativePath(for: original) == "\(Self.docId)/original.pdf")
        #expect(store.url(forRelativePath: "\(Self.docId)/original.pdf").standardizedFileURL
            == original.standardizedFileURL)

        let outside = store.rootURL.appending(path: "StudyReader.sqlite", directoryHint: .notDirectory)
        #expect(store.relativePath(for: outside) == nil)
    }

    @Test func createRootDirectoriesIsIdempotent() throws {
        let store = TestFileStore.make()
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
        try store.createRootDirectories()
        let folder = try store.createDocumentFolder(documentId: Self.docId)
        let file = store.originalFileURL(documentId: Self.docId, fileExtension: "pdf")
        try Data("pdf".utf8).write(to: file)
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))

        try store.deleteDocumentFolder(documentId: Self.docId)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))

        try store.deleteDocumentFolder(documentId: Self.docId)
    }

    @Test func rejectsInvalidDocumentIds() throws {
        let store = TestFileStore.make()
        try store.createRootDirectories()
        let invalidIds = ["", "..", "a/b", "not-a-uuid"]

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
}
