import Foundation

enum FileStoreError: Error, Equatable, LocalizedError {
    case invalidDocumentId(String)

    var errorDescription: String? {
        switch self {
        case .invalidDocumentId: "Invalid document identifier."
        }
    }
}

/// The only code that builds file paths under the library root (ARCHITECTURE §13).
/// Layout: `<root>/StudyReader.sqlite`, `<root>/Documents/<id>/…`.
struct FileStore: Sendable, Equatable {
    /// .../Application Support/StudyReader
    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// The user's library in Application Support (inside the sandbox container).
    static func applicationSupport() throws -> FileStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return FileStore(rootURL: support.appending(path: "StudyReader", directoryHint: .isDirectory))
    }

    var databaseURL: URL {
        rootURL.appending(path: "StudyReader.sqlite", directoryHint: .notDirectory)
    }

    var documentsURL: URL {
        rootURL.appending(path: "Documents", directoryHint: .isDirectory)
    }

    func documentFolderURL(documentId: String) -> URL {
        documentsURL.appending(path: documentId, directoryHint: .isDirectory)
    }

    func originalFileURL(documentId: String, fileExtension: String) -> URL {
        documentFolderURL(documentId: documentId)
            .appending(path: "original.\(fileExtension)", directoryHint: .notDirectory)
    }

    func coverURL(documentId: String) -> URL {
        documentFolderURL(documentId: documentId)
            .appending(path: "cover.png", directoryHint: .notDirectory)
    }

    func imagesFolderURL(documentId: String) -> URL {
        documentFolderURL(documentId: documentId)
            .appending(path: "images", directoryHint: .isDirectory)
    }

    func snapshotURL(documentId: String, highlightId: String) -> URL {
        documentFolderURL(documentId: documentId)
            .appending(path: "snapshots", directoryHint: .isDirectory)
            .appending(path: "\(highlightId).png", directoryHint: .notDirectory)
    }

    /// Resolves a database-stored path (relative to `documentsURL`, e.g. `"<id>/original.pdf"`).
    func url(forRelativePath relativePath: String) -> URL {
        documentsURL.appending(path: relativePath, directoryHint: .notDirectory)
    }

    /// Inverse of `url(forRelativePath:)`. Returns nil when `url` is not inside `documentsURL`.
    func relativePath(for url: URL) -> String? {
        let base = Self.trimmedPath(documentsURL)
        let target = Self.trimmedPath(url)
        let prefix = base + "/"
        guard target.hasPrefix(prefix) else { return nil }
        let relative = String(target.dropFirst(prefix.count))
        return relative.isEmpty ? nil : relative
    }

    /// Creates the root and `Documents/` if missing.
    func createRootDirectories() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
    }

    /// Creates `Documents/<id>/` and returns it.
    @discardableResult
    func createDocumentFolder(documentId: String) throws -> URL {
        try Self.validate(documentId)
        let folder = documentFolderURL(documentId: documentId)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Removes `Documents/<id>/` recursively. A missing folder is not an error.
    func deleteDocumentFolder(documentId: String) throws {
        try Self.validate(documentId)
        let folder = documentFolderURL(documentId: documentId)
        guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    /// Names of `Documents/` subfolders that are UUIDs, sorted. Empty when `Documents/` is missing.
    func documentFolderIds() throws -> [String] {
        let documentsPath = documentsURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: documentsPath) else { return [] }
        let entries = try FileManager.default.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try entries
            .filter { entry in
                let isDirectory = try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
                return isDirectory && UUID(uuidString: entry.lastPathComponent) != nil
            }
            .map(\.lastPathComponent)
            .sorted()
    }

    // MARK: - Helpers

    private static func validate(_ documentId: String) throws {
        guard UUID(uuidString: documentId) != nil else {
            throw FileStoreError.invalidDocumentId(documentId)
        }
    }

    /// Standardized path without a trailing slash, so prefix comparisons are stable.
    private static func trimmedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
