import Foundation

enum FileStoreError: Error, Equatable, LocalizedError {
    case invalidDocumentId(String)
    case invalidHighlightId(String)
    case invalidFileExtension(String)

    var errorDescription: String? {
        switch self {
        case .invalidDocumentId: "Invalid document identifier."
        case .invalidHighlightId: "Invalid highlight identifier."
        case .invalidFileExtension: "Invalid file extension."
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

    /// true when `UUID(uuidString: id)?.uuidString == id` (canonical uppercase form, as `UUID().uuidString` makes).
    static func isCanonicalId(_ id: String) -> Bool {
        UUID(uuidString: id)?.uuidString == id
    }

    func documentFolderURL(documentId: String) throws -> URL {
        try Self.validateDocumentId(documentId)
        return documentsURL.appending(path: documentId, directoryHint: .isDirectory)
    }

    func originalFileURL(documentId: String, fileExtension: String) throws -> URL {
        let folder = try documentFolderURL(documentId: documentId)
        try Self.validateFileExtension(fileExtension)
        return folder.appending(path: "original.\(fileExtension)", directoryHint: .notDirectory)
    }

    func coverURL(documentId: String) throws -> URL {
        try documentFolderURL(documentId: documentId)
            .appending(path: "cover.png", directoryHint: .notDirectory)
    }

    func imagesFolderURL(documentId: String) throws -> URL {
        try documentFolderURL(documentId: documentId)
            .appending(path: "images", directoryHint: .isDirectory)
    }

    func snapshotURL(documentId: String, highlightId: String) throws -> URL {
        let folder = try documentFolderURL(documentId: documentId)
        try Self.validateHighlightId(highlightId)
        return folder
            .appending(path: "snapshots", directoryHint: .isDirectory)
            .appending(path: "\(highlightId).png", directoryHint: .notDirectory)
    }

    /// Resolves a database-stored path (relative to `documentsURL`, e.g. `"<id>/original.pdf"`).
    /// Returns nil for anything that is not `<canonical id>/…` inside `Documents/`.
    func url(forRelativePath relativePath: String) -> URL? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return nil }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ $0 != "" && $0 != "." && $0 != ".." }),
              let first = components.first,
              Self.isCanonicalId(String(first))
        else { return nil }
        let resolved = documentsURL.appending(path: relativePath, directoryHint: .notDirectory)
        let target = Self.trimmedPath(resolved)
        guard target.hasPrefix(Self.trimmedPath(documentsURL) + "/") else { return nil }
        return resolved.standardizedFileURL
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
        let folder = try documentFolderURL(documentId: documentId)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Removes `Documents/<id>/` recursively. A missing folder is not an error.
    func deleteDocumentFolder(documentId: String) throws {
        let folder = try documentFolderURL(documentId: documentId)
        guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    /// Names of `Documents/` subfolders that are canonical document IDs, sorted.
    /// Empty when `Documents/` is missing.
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
                return isDirectory && Self.isCanonicalId(entry.lastPathComponent)
            }
            .map(\.lastPathComponent)
            .sorted()
    }

    // MARK: - Helpers

    private static func validateDocumentId(_ id: String) throws {
        guard isCanonicalId(id) else { throw FileStoreError.invalidDocumentId(id) }
    }

    private static func validateHighlightId(_ id: String) throws {
        guard isCanonicalId(id) else { throw FileStoreError.invalidHighlightId(id) }
    }

    /// 1–10 ASCII characters, each `a`–`z` or `0`–`9`.
    private static func validateFileExtension(_ fileExtension: String) throws {
        let bytes = fileExtension.utf8
        let isValid = (1...10).contains(bytes.count) && bytes.allSatisfy { byte in
            (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
                || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
        }
        guard isValid else { throw FileStoreError.invalidFileExtension(fileExtension) }
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
