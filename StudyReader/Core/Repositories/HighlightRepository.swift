import Foundation
import GRDB

/// Highlight rows for the readers, popover and panel (ARCHITECTURE §4–§5). Frequent non-text saves
/// (color, anchor) use column-limited `update(db, columns:)` so `highlight_fts_au` doesn't re-index (ADR-0013).
struct HighlightRepository: Sendable {
    private let writer: any DatabaseWriter

    init(database: AppDatabase) {
        self.writer = database.writer
    }

    /// One read: the matching highlights, then their tags in one more query over the same conditions (no per-row fetch).
    func browse(filter: HighlightBrowserFilter, sort: HighlightBrowserSort) async throws -> [HighlightListItem] {
        try await writer.read { db in
            try HighlightBrowseSQL.items(db, filter: filter, sort: sort)
        }
    }

    /// Live version of `browse(filter:sort:)`. The first element is the current value.
    func observeBrowse(filter: HighlightBrowserFilter, sort: HighlightBrowserSort) -> AsyncValueObservation<[HighlightListItem]> {
        ValueObservation
            .tracking { db in
                try HighlightBrowseSQL.items(db, filter: filter, sort: sort)
            }
            .values(in: writer)
    }

    /// One transaction: the highlight, one `HighlightTag` per distinct tag id (duplicates ignored), then, when
    /// `passiveCard` is given, `ReviewCardRepository.insertAutomaticPassiveCard` (which checks the category itself).
    func insert(_ highlight: Highlight, tagIds: [String] = [], passiveCard: ReviewCard? = nil) async throws {
        try await writer.write { db in
            try highlight.insert(db)
            for tagId in Self.uniqueInOrder(tagIds) {
                try HighlightTag(highlightId: highlight.id, tagId: tagId).insert(db)
            }
            if let passiveCard {
                _ = try ReviewCardRepository.insertAutomaticPassiveCard(passiveCard, db)
            }
        }
    }

    func fetch(id: String) async throws -> Highlight? {
        try await writer.read { db in
            try Highlight.fetchOne(db, key: id)
        }
    }

    /// Ordered by positionKey, then createdAt, then id.
    func fetchForDocument(_ documentId: String) async throws -> [Highlight] {
        try await writer.read { db in
            try Self.forDocument(documentId, db)
        }
    }

    /// Live version of `fetchForDocument(_:)`. The first element is the current value.
    func observeForDocument(_ documentId: String) -> AsyncValueObservation<[Highlight]> {
        ValueObservation
            .tracking { db in
                try Self.forDocument(documentId, db)
            }
            .values(in: writer)
    }

    /// Live single row. The first element is the current value; nil when the row is missing.
    func observeHighlight(id: String) -> AsyncValueObservation<Highlight?> {
        ValueObservation
            .tracking { db in
                try Highlight.fetchOne(db, key: id)
            }
            .values(in: writer)
    }

    /// Updates `color` and `updatedAt`. Missing row: `RepositoryError.notFound`.
    func updateColor(id: String, color: HighlightColor, at date: Date) async throws {
        try await update(id: id, columns: ["color", "updatedAt"]) { highlight in
            highlight.color = color
            highlight.updatedAt = date
        }
    }

    /// Updates `note` (stored as given) and `updatedAt`. The note is re-indexed. Missing row: `RepositoryError.notFound`.
    func updateNote(id: String, note: String, at date: Date) async throws {
        try await update(id: id, columns: ["note", "updatedAt"]) { highlight in
            highlight.note = note
            highlight.updatedAt = date
        }
    }

    /// Re-anchoring result (ARCHITECTURE §5.3). Missing row: `RepositoryError.notFound`.
    func updateAnchor(
        id: String,
        anchor: HighlightAnchor,
        positionKey: Double,
        status: AnchorStatus,
        at date: Date
    ) async throws {
        try await update(id: id, columns: ["anchor", "positionKey", "anchorStatus", "updatedAt"]) { highlight in
            highlight.anchor = anchor
            highlight.positionKey = positionKey
            highlight.anchorStatus = status
            highlight.updatedAt = date
        }
    }

    /// Deletes the row (SQL cascades remove tag links, review cards and embeddings), then removes the
    /// snapshot file if `imagePath` resolves. A missing file is not an error. Returns false if no row existed.
    @discardableResult
    func delete(id: String, fileStore: FileStore) async throws -> Bool {
        let removed = try await writer.write { db -> Highlight? in
            guard let highlight = try Highlight.fetchOne(db, key: id) else { return nil }
            _ = try highlight.delete(db)
            return highlight
        }
        guard let removed else { return false }
        try Self.removeSnapshotFile(relativePath: removed.imagePath, fileStore: fileStore)
        return true
    }

    /// Deletes the row only when it is still bare: `note` is empty after trimming whitespace and newlines,
    /// `editedText` is nil, and no `highlightTag` row references it. The check and the delete run in ONE write
    /// transaction, so a note or tag written just before can't slip between them. On delete, removes the snapshot
    /// file like `delete(id:fileStore:)`. Returns true when the row was deleted; false when it is missing or
    /// annotated (nothing changed).
    @discardableResult
    func deleteIfUnannotated(id: String, fileStore: FileStore) async throws -> Bool {
        let removed = try await writer.write { db -> Highlight? in
            guard let highlight = try Highlight.fetchOne(db, key: id) else { return nil }
            guard highlight.editedText == nil,
                  highlight.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            let tagLinks = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM highlightTag WHERE highlightId = ?",
                arguments: [id]
            ) ?? 0
            guard tagLinks == 0 else { return nil }
            _ = try highlight.delete(db)
            return highlight
        }
        guard let removed else { return false }
        try Self.removeSnapshotFile(relativePath: removed.imagePath, fileStore: fileStore)
        return true
    }

    /// Deletes the rows in one transaction, then removes each snapshot file. Unknown ids are skipped.
    /// Returns the number deleted.
    @discardableResult
    func delete(ids: [String], fileStore: FileStore) async throws -> Int {
        let removed = try await writer.write { db -> [Highlight] in
            let rows = try Highlight.filter(keys: ids).fetchAll(db)
            _ = try Highlight.filter(keys: ids).deleteAll(db)
            return rows
        }
        for highlight in removed {
            try Self.removeSnapshotFile(relativePath: highlight.imagePath, fileStore: fileStore)
        }
        return removed.count
    }

    /// Sets `color` and `updatedAt` on each existing row in one transaction. Unknown ids are skipped.
    /// Returns the number updated.
    @discardableResult
    func updateColor(ids: [String], color: HighlightColor, at date: Date) async throws -> Int {
        try await writer.write { db in
            var updated = 0
            for id in Self.uniqueInOrder(ids) {
                guard var highlight = try Highlight.fetchOne(db, key: id) else { continue }
                highlight.color = color
                highlight.updatedAt = date
                try highlight.update(db, columns: ["color", "updatedAt"])
                updated += 1
            }
            return updated
        }
    }

    /// Fetches the row and updates only `columns` in the same write. Missing row: `RepositoryError.notFound`.
    private func update(
        id: String,
        columns: [String],
        _ change: @escaping @Sendable (inout Highlight) -> Void
    ) async throws {
        try await writer.write { db in
            guard var highlight = try Highlight.fetchOne(db, key: id) else {
                throw RepositoryError.notFound
            }
            change(&highlight)
            try highlight.update(db, columns: columns)
        }
    }

    private static func forDocument(_ documentId: String, _ db: Database) throws -> [Highlight] {
        try Highlight
            .filter(Column("documentId") == documentId)
            .order(Column("positionKey").asc, Column("createdAt").asc, Column("id").asc)
            .fetchAll(db)
    }

    /// Removes `relativePath` (resolved by `fileStore.url(forRelativePath:)`) when the file exists.
    private static func removeSnapshotFile(relativePath: String?, fileStore: FileStore) throws {
        guard let relativePath, let url = fileStore.url(forRelativePath: relativePath) else { return }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// The ids with repeats removed, first occurrence kept.
    private static func uniqueInOrder(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}
