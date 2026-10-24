import Foundation

/// Applies cover changes (SPEC F-11, ADR-0016). All file paths go through `FileStore`; rendering and conversion
/// run in a detached task, never on the main actor.
struct CoverService: Sendable {
    private let fileStore: FileStore
    private let documents: DocumentRepository

    init(fileStore: FileStore, documents: DocumentRepository) {
        self.fileStore = fileStore
        self.documents = documents
    }

    /// PDF: renders page 0 to `cover.png` and stores `coverSource = .automatic`.
    /// Markdown: deletes `cover.png` if present and clears `coverPath`.
    func resetCover(documentId: String) async throws {
        let document = try await fetch(documentId)
        let coverURL = try fileStore.coverURL(documentId: documentId)
        switch document.fileType {
        case .pdf:
            let original = try originalURL(of: document)
            try await replaceCover(at: coverURL) { temporary in
                try CoverRenderer.renderPDFPage(fileAt: original, pageIndex: 0, to: temporary)
            }
            try await documents.updateCover(
                id: documentId, coverPath: try relativeCoverPath(coverURL), coverSource: .automatic
            )
        case .markdown:
            try await documents.updateCover(id: documentId, coverPath: nil, coverSource: .automatic)
            try Self.removeIfPresent(coverURL)
        }
    }

    /// Converts `imageURL` to `cover.png` and stores `coverSource = .custom`. The URL is user-selected;
    /// the caller handles its security scope.
    func setCustomCover(documentId: String, imageURL: URL) async throws {
        _ = try await fetch(documentId)
        let coverURL = try fileStore.coverURL(documentId: documentId)
        try await replaceCover(at: coverURL) { temporary in
            try CoverRenderer.convertImage(at: imageURL, to: temporary)
        }
        try await documents.updateCover(
            id: documentId, coverPath: try relativeCoverPath(coverURL), coverSource: .custom
        )
    }

    /// PDF only: renders `pageIndex` to `cover.png` and stores `coverSource = .page`.
    /// A Markdown document throws `CoverError.cannotOpen`.
    func usePageAsCover(documentId: String, pageIndex: Int) async throws {
        let document = try await fetch(documentId)
        guard document.fileType == .pdf else { throw CoverError.cannotOpen }
        let original = try originalURL(of: document)
        let coverURL = try fileStore.coverURL(documentId: documentId)
        try await replaceCover(at: coverURL) { temporary in
            try CoverRenderer.renderPDFPage(fileAt: original, pageIndex: pageIndex, to: temporary)
        }
        try await documents.updateCover(
            id: documentId, coverPath: try relativeCoverPath(coverURL), coverSource: .page
        )
    }

    // MARK: - Helpers

    private func fetch(_ documentId: String) async throws -> LibraryDocument {
        guard let document = try await documents.fetch(id: documentId) else { throw RepositoryError.notFound }
        return document
    }

    private func originalURL(of document: LibraryDocument) throws -> URL {
        guard let url = fileStore.url(forRelativePath: document.storedPath) else { throw CoverError.cannotOpen }
        return url
    }

    private func relativeCoverPath(_ coverURL: URL) throws -> String {
        guard let path = fileStore.relativePath(for: coverURL) else { throw CoverError.cannotOpen }
        return path
    }

    /// Runs `produce` in a detached task against a temporary file in the cover's folder, then replaces the cover
    /// with it atomically. A failed `produce` leaves the old cover untouched.
    private func replaceCover(
        at coverURL: URL,
        produce: @escaping @Sendable (URL) throws -> Void
    ) async throws {
        try await Task.detached {
            let fileManager = FileManager.default
            let folder = coverURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let temporary = folder.appending(path: ".cover-\(UUID().uuidString).png", directoryHint: .notDirectory)
            defer { try? fileManager.removeItem(at: temporary) }
            try produce(temporary)
            if fileManager.fileExists(atPath: coverURL.path(percentEncoded: false)) {
                _ = try fileManager.replaceItemAt(coverURL, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: coverURL)
            }
        }.value
    }

    private static func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
