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
}
