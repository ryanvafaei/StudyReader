import Foundation
@testable import StudyReader

enum TestFileStore {
    /// FileStore rooted at `temporaryDirectory/StudyReaderTests/<UUID>/StudyReader`.
    /// Directories are not created; call `createRootDirectories()` when needed.
    static func make() -> FileStore {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "StudyReaderTests", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "StudyReader", directoryHint: .isDirectory)
        return FileStore(rootURL: root)
    }

    /// Removes the per-test folder `<parent>/<UUID>/` above `store.rootURL` (`<parent>/<UUID>/StudyReader`).
    /// Does nothing unless rootURL.lastPathComponent == "StudyReader", the grandparent folder's name is
    /// "StudyReaderTests" or "StudyReader-InMemory", and the standardized path starts with the standardized
    /// FileManager.default.temporaryDirectory path. Errors are ignored (try?).
    static func remove(_ store: FileStore) {
        let root = store.rootURL.standardizedFileURL
        guard root.lastPathComponent == "StudyReader" else { return }
        let uuidFolder = root.deletingLastPathComponent()
        let grandparentName = uuidFolder.deletingLastPathComponent().lastPathComponent
        guard grandparentName == "StudyReaderTests" || grandparentName == "StudyReader-InMemory" else { return }
        let temporaryPath = FileManager.default.temporaryDirectory.standardizedFileURL.path(percentEncoded: false)
        guard root.path(percentEncoded: false).hasPrefix(temporaryPath) else { return }
        try? FileManager.default.removeItem(at: uuidFolder)
    }
}
