import Foundation
import GRDB

/// Export data: loads highlights, notes and metadata for an export scope, and stores export targets (ARCHITECTURE §9,
/// ADR-0018). No network. Highlight loading uses `HighlightBrowseSQL.items`, the same SQL as the browser, so scopes
/// and the browser agree. Each export reads inside one `writer.read` (one snapshot).
struct ExportRepository: Sendable {
    private let writer: any DatabaseWriter

    init(database: AppDatabase) {
        self.writer = database.writer
    }

    // MARK: Content

    /// document → its title; tag → "#" + name; category → its name; themedReview → its name; all → "All highlights".
    /// A missing document, tag, category or themed review: `RepositoryError.notFound`.
    func scopeName(for scope: ExportScope) async throws -> String {
        try await writer.read { db in
            try Self.scopeName(for: scope, db)
        }
    }

    /// One read: the scope name, the highlights and the documents with their notes, all from one snapshot.
    func content(for scope: ExportScope) async throws -> ExportContent {
        try await writer.read { db in
            let name = try Self.scopeName(for: scope, db)
            let filter = try Self.browseFilter(for: scope, db)
            let items = try HighlightBrowseSQL.items(db, filter: filter, sort: .documentPosition)
            let noteOnlyDocuments: NoteOnlyDocuments? = switch scope.kind {
            case .category: NoteOnlyDocuments(categoryId: scope.id)
            case .all: NoteOnlyDocuments(categoryId: nil)
            case .document, .tag, .themedReview: nil
            }
            return try Self.assemble(
                db,
                scopeName: name,
                items: items,
                extraDocumentId: scope.kind == .document ? scope.id : nil,
                noteOnlyDocuments: noteOnlyDocuments
            )
        }
    }

    /// Only the given highlights (the one-off "Export selection"); documents that contribute at least one, with their notes.
    /// One read, filtered in SQL by `onlyIds`.
    func content(forHighlightIds ids: [String], scopeName: String) async throws -> ExportContent {
        try await writer.read { db in
            let items = try HighlightBrowseSQL.items(
                db,
                filter: HighlightBrowserFilter(),
                sort: .documentPosition,
                onlyIds: Set(ids)
            )
            return try Self.assemble(db, scopeName: scopeName, items: items, extraDocumentId: nil, noteOnlyDocuments: nil)
        }
    }

    /// Emits when anything an export reads changes: highlight, highlightTag, tag, document, documentTag, documentNote
    /// or category. The value is a digest of the exported columns; the first element is the current value (T74).
    ///
    /// The digest uses `Hasher`, which is seeded per process: compare tokens only within one app run.
    func observeChangeToken() -> AsyncValueObservation<Int> {
        ValueObservation
            .tracking { db in
                var hasher = Hasher()
                for sql in Self.changeTokenQueries {
                    for row in try Row.fetchAll(db, sql: sql) {
                        hasher.combine(row)
                    }
                }
                return hasher.finalize()
            }
            .values(in: writer)
    }

    /// Themed reviews to pick as an export scope, by name.
    func fetchThemedReviews() async throws -> [ThemedReview] {
        try await writer.read { db in
            try ThemedReview.order(Column("name").collating(.localizedCaseInsensitiveCompare), Column("id")).fetchAll(db)
        }
    }

    // MARK: Targets

    /// Ordered by `createdAt`, then id.
    func fetchTargets() async throws -> [ExportTarget] {
        try await writer.read { db in
            try Self.allTargets(db)
        }
    }

    func observeTargets() -> AsyncValueObservation<[ExportTarget]> {
        ValueObservation
            .tracking { db in
                try Self.allTargets(db)
            }
            .values(in: writer)
    }

    func fetchTarget(id: String) async throws -> ExportTarget? {
        try await writer.read { db in
            try ExportTarget.fetchOne(db, key: id)
        }
    }

    /// The first target (oldest) whose scope equals `scope`.
    func target(for scope: ExportScope) async throws -> ExportTarget? {
        try await fetchTargets().first { $0.scope == scope }
    }

    func insertTarget(_ target: ExportTarget) async throws {
        try await writer.write { db in
            try target.insert(db)
        }
    }

    /// Updates `options`, `title`. Missing row: `RepositoryError.notFound`.
    func updateOptions(id: String, options: ExportOptions, title: String) async throws {
        try await update(id: id, columns: ["options", "title"]) { target in
            target.options = options
            target.title = title
        }
    }

    func setKeepInSync(id: String, _ on: Bool) async throws {
        try await update(id: id, columns: ["keepInSync"]) { target in
            target.keepInSync = on
        }
    }

    /// Column-limited: `lastStatus` and `lastError` always; `googleFileId`, `googleFolderId`, `format` and
    /// `lastExportedAt` only when non-nil. Missing row: `RepositoryError.notFound`.
    func recordResult(
        id: String,
        status: ExportStatus,
        error: String?,
        fileId: String?,
        folderId: String?,
        format: ExportFormat?,
        exportedAt: Date?
    ) async throws {
        var columns = ["lastStatus", "lastError"]
        if fileId != nil { columns.append("googleFileId") }
        if folderId != nil { columns.append("googleFolderId") }
        if format != nil { columns.append("format") }
        if exportedAt != nil { columns.append("lastExportedAt") }
        try await update(id: id, columns: columns) { target in
            target.lastStatus = status.rawValue
            target.lastError = error
            if let fileId { target.googleFileId = fileId }
            if let folderId { target.googleFolderId = folderId }
            if let format { target.format = format }
            if let exportedAt { target.lastExportedAt = exportedAt }
        }
    }

    /// "Create new Doc": forgets the Google file ID.
    func clearFileId(id: String) async throws {
        try await update(id: id, columns: ["googleFileId"]) { target in
            target.googleFileId = nil
        }
    }

    /// Deletes the local row only. Never touches Google.
    func removeTarget(id: String) async throws {
        try await writer.write { db in
            _ = try ExportTarget.deleteOne(db, key: id)
        }
    }

    // MARK: Helpers

    private func update(
        id: String,
        columns: [String],
        _ change: @escaping @Sendable (inout ExportTarget) -> Void
    ) async throws {
        try await writer.write { db in
            guard var target = try ExportTarget.fetchOne(db, key: id) else {
                throw RepositoryError.notFound
            }
            change(&target)
            try target.update(db, columns: columns)
        }
    }

    private static func allTargets(_ db: Database) throws -> [ExportTarget] {
        try ExportTarget.order(Column("createdAt").asc, Column("id").asc).fetchAll(db)
    }

    private static func scopeName(for scope: ExportScope, _ db: Database) throws -> String {
        switch scope.kind {
        case .all:
            return "All highlights"
        case .document:
            guard let id = scope.id, let document = try LibraryDocument.fetchOne(db, key: id) else {
                throw RepositoryError.notFound
            }
            return document.title
        case .tag:
            guard let id = scope.id, let tag = try LibraryTag.fetchOne(db, key: id) else {
                throw RepositoryError.notFound
            }
            return "#" + tag.name
        case .category:
            guard let id = scope.id, let category = try DocumentCategory.fetchOne(db, key: id) else {
                throw RepositoryError.notFound
            }
            return category.name
        case .themedReview:
            guard let id = scope.id, let review = try ThemedReview.fetchOne(db, key: id) else {
                throw RepositoryError.notFound
            }
            return review.name
        }
    }

    private static func browseFilter(for scope: ExportScope, _ db: Database) throws -> HighlightBrowserFilter {
        var filter = HighlightBrowserFilter()
        switch scope.kind {
        case .all:
            break
        case .document:
            filter.documentIds = scope.id.map { [$0] } ?? []
        case .tag:
            filter.tagIds = scope.id.map { [$0] } ?? []
        case .category:
            filter.categoryIds = scope.id.map { [$0] } ?? []
        case .themedReview:
            guard let id = scope.id, let review = try ThemedReview.fetchOne(db, key: id) else {
                throw RepositoryError.notFound
            }
            filter = review.filter.highlightBrowserFilter
        }
        return filter
    }

    /// Documents without highlights that still belong in the export because they have a note.
    private struct NoteOnlyDocuments {
        /// nil: every document.
        var categoryId: String?
    }

    /// Builds the export from rows already read in the caller's transaction. Batched: one query each for the notes,
    /// the documents and their categories.
    private static func assemble(
        _ db: Database,
        scopeName: String,
        items: [HighlightListItem],
        extraDocumentId: String?,
        noteOnlyDocuments: NoteOnlyDocuments?
    ) throws -> ExportContent {
        var documentIds = Set(items.map { $0.highlight.documentId })
        if let extraDocumentId { documentIds.insert(extraDocumentId) }
        var notes = try noteTexts(db, documentIds: documentIds)
        if let noteOnlyDocuments {
            let noteOnly = try noteTexts(db, categoryId: noteOnlyDocuments.categoryId)
            notes.merge(noteOnly) { current, _ in current }
            documentIds.formUnion(noteOnly.keys)
        }

        let documents = try LibraryDocument.filter(keys: Array(documentIds)).fetchAll(db)
        let categoryIds = Array(Set(documents.map(\.categoryId)))
        let categoryNames = Dictionary(
            uniqueKeysWithValues: try DocumentCategory.filter(keys: categoryIds).fetchAll(db).map { ($0.id, $0.name) }
        )

        var byDocument: [String: [ExportHighlight]] = [:]
        for item in items {
            byDocument[item.highlight.documentId, default: []].append(Self.exportHighlight(item))
        }

        var exportDocuments = documents.map { document in
            let sorted = (byDocument[document.id] ?? []).sorted {
                ($0.positionKey, $0.id) < ($1.positionKey, $1.id)
            }
            return ExportDocument(
                id: document.id,
                title: document.title,
                author: document.author,
                categoryName: categoryNames[document.categoryId] ?? "",
                documentNote: notes[document.id],
                highlights: sorted
            )
        }
        exportDocuments.sort { left, right in
            let order = left.title.localizedStandardCompare(right.title)
            return order == .orderedSame ? left.id < right.id : order == .orderedAscending
        }
        return ExportContent(scopeName: scopeName, documents: exportDocuments)
    }

    /// Trimmed, non-empty note bodies keyed by document id, for the given documents.
    /// Trimming happens in Swift because SQL `TRIM` strips only spaces.
    private static func noteTexts(_ db: Database, documentIds: Set<String>) throws -> [String: String] {
        trimmedBodies(try DocumentNote.filter(keys: Array(documentIds)).fetchAll(db))
    }

    /// Trimmed, non-empty note bodies of the documents in `categoryId` (every document when nil).
    /// The category filter runs in SQL.
    private static func noteTexts(_ db: Database, categoryId: String?) throws -> [String: String] {
        guard let categoryId else {
            return trimmedBodies(try DocumentNote.fetchAll(db))
        }
        let notes = try DocumentNote.fetchAll(
            db,
            sql: """
                SELECT documentNote.* FROM documentNote
                JOIN document ON document.id = documentNote.documentId
                WHERE document.categoryId = ?
                """,
            arguments: [categoryId]
        )
        return trimmedBodies(notes)
    }

    private static func trimmedBodies(_ notes: [DocumentNote]) -> [String: String] {
        notes.reduce(into: [String: String]()) { result, note in
            let trimmed = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result[note.documentId] = trimmed }
        }
    }

    private static func exportHighlight(_ item: HighlightListItem) -> ExportHighlight {
        let highlight = item.highlight
        let body: String
        if highlight.kind == .image {
            body = ""
        } else if let edited = highlight.editedText {
            body = RichTextMarkdown.escape(edited)
        } else if !highlight.richText.isEmpty {
            body = highlight.richText
        } else {
            body = RichTextMarkdown.escape(highlight.text)
        }
        return ExportHighlight(
            id: highlight.id,
            documentId: highlight.documentId,
            kind: highlight.kind,
            color: highlight.color,
            pageIndex: highlight.pageIndex,
            body: body,
            note: highlight.note.trimmingCharacters(in: .whitespacesAndNewlines),
            tagNames: item.tagNames,
            positionKey: highlight.positionKey
        )
    }

    /// Columns an export reads, each table ordered by its key. Text columns enter as lengths; `updatedAt` covers edits.
    private static let changeTokenQueries = [
        """
        SELECT id, documentId, kind, color, pageIndex, positionKey, updatedAt, LENGTH(text), LENGTH(richText), \
        LENGTH(editedText), LENGTH(note) FROM highlight ORDER BY id
        """,
        "SELECT highlightId, tagId FROM highlightTag ORDER BY highlightId, tagId",
        "SELECT id, name FROM tag ORDER BY id",
        "SELECT id, title, author, categoryId FROM document ORDER BY id",
        "SELECT documentId, tagId FROM documentTag ORDER BY documentId, tagId",
        "SELECT documentId, updatedAt, LENGTH(body) FROM documentNote ORDER BY documentId",
        "SELECT id, name FROM category ORDER BY id",
    ]
}
