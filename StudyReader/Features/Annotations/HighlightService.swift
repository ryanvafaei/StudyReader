import Foundation

/// What a reader engine hands over for a text selection. view is .pdf or .markdown in Phase 1.
struct NewTextHighlight: Sendable, Equatable {
    var documentId: String
    var view: ReaderViewKind
    var anchor: HighlightAnchor          // .pdf or .text
    var text: String                     // plain selected text
    var richText: String                 // F-07 Markdown subset (escaped plain text for PDF view in Phase 1)
    var pageIndex: Int?                  // first page for PDF; nil for Markdown
    var positionKey: Double
    var color: HighlightColor
}

/// A snapshot (F-08). pngData is already rendered (SnapshotService, T61).
struct NewImageHighlight: Sendable, Equatable {
    var documentId: String
    var pageIndex: Int
    var rect: CGRectCodable              // page space, already clipped
    var positionKey: Double
    var color: HighlightColor
    var pngData: Data
}

enum HighlightServiceError: Error, Equatable, LocalizedError {
    case emptySelection                  // "Select some text to highlight."
    case snapshotWriteFailed             // "The snapshot couldn't be saved."

    var errorDescription: String? {
        switch self {
        case .emptySelection: "Select some text to highlight."
        case .snapshotWriteFailed: "The snapshot couldn't be saved."
        }
    }
}

/// Turns selections and snapshots into stored highlights and changes or deletes them (SPEC F-06, F-08).
/// Engines compute anchors and position keys; this service stores them with fresh ids and dates from `now()`.
actor HighlightService {
    private let highlights: HighlightRepository
    private let tags: TagRepository
    private let fileStore: FileStore
    private let now: any Now
    /// The auto-highlight that ⌘Z may undo. Any call other than an auto `createText` forgets it.
    private var lastAutoHighlightId: String?

    init(highlights: HighlightRepository, tags: TagRepository, fileStore: FileStore, now: any Now) {
        self.highlights = highlights
        self.tags = tags
        self.fileStore = fileStore
        self.now = now
    }

    /// Stores text as given; if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty → .emptySelection.
    /// Creates Highlight(id: UUID().uuidString, kind: .text, createdAt = updatedAt = now(), …) and inserts it.
    /// isAuto == true remembers the id as the undoable auto-highlight; any other call below forgets it.
    func createText(_ new: NewTextHighlight, isAuto: Bool) async throws -> Highlight {
        forgetAutoHighlight()
        guard !new.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HighlightServiceError.emptySelection
        }
        let date = now()
        let highlight = Highlight(
            id: UUID().uuidString,
            documentId: new.documentId,
            kind: .text,
            view: new.view,
            color: new.color,
            text: new.text,
            richText: new.richText,
            pageIndex: new.pageIndex,
            positionKey: new.positionKey,
            anchor: new.anchor,
            createdAt: date,
            updatedAt: date
        )
        try await highlights.insert(highlight)
        if isAuto {
            lastAutoHighlightId = highlight.id
        }
        return highlight
    }

    /// Writes pngData to fileStore.snapshotURL(documentId:highlightId:) (creating snapshots/), then inserts
    /// kind .image, view .pdf, anchor .image(ImageAnchor(pageIndex:rect:)), imagePath = relativePath(for:).
    /// If the insert fails, deletes the PNG and rethrows. If writing fails, throws .snapshotWriteFailed.
    func createImage(_ new: NewImageHighlight) async throws -> Highlight {
        forgetAutoHighlight()
        let id = UUID().uuidString
        let url = try fileStore.snapshotURL(documentId: new.documentId, highlightId: id)
        guard let imagePath = fileStore.relativePath(for: url) else {
            throw HighlightServiceError.snapshotWriteFailed
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try new.pngData.write(to: url, options: .atomic)
        } catch {
            throw HighlightServiceError.snapshotWriteFailed
        }
        let date = now()
        let highlight = Highlight(
            id: id,
            documentId: new.documentId,
            kind: .image,
            view: .pdf,
            color: new.color,
            pageIndex: new.pageIndex,
            positionKey: new.positionKey,
            anchor: .image(ImageAnchor(pageIndex: new.pageIndex, rect: new.rect)),
            imagePath: imagePath,
            createdAt: date,
            updatedAt: date
        )
        do {
            try await highlights.insert(highlight)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        return highlight
    }

    /// Deletes the remembered auto-highlight and returns its id; nil if there is none (then does nothing).
    func undoLastAutoHighlight() async throws -> String? {
        guard let id = lastAutoHighlightId else { return nil }
        lastAutoHighlightId = nil
        try await highlights.delete(id: id, fileStore: fileStore)
        return id
    }

    func setColor(id: String, color: HighlightColor) async throws {
        forgetAutoHighlight()
        try await highlights.updateColor(id: id, color: color, at: now())
    }

    func delete(id: String) async throws {
        forgetAutoHighlight()
        try await highlights.delete(id: id, fileStore: fileStore)
    }

    func delete(ids: [String]) async throws {
        forgetAutoHighlight()
        try await highlights.delete(ids: ids, fileStore: fileStore)
    }

    func setColor(ids: [String], color: HighlightColor) async throws {
        forgetAutoHighlight()
        try await highlights.updateColor(ids: ids, color: color, at: now())
    }

    private func forgetAutoHighlight() {
        lastAutoHighlightId = nil
    }
}
