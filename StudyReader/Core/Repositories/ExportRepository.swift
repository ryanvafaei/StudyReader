import Foundation
import GRDB

/// Export data: loads highlights, notes and metadata for an export scope, and stores export targets (ARCHITECTURE §9,
/// ADR-0018). No network. Highlight loading reuses `HighlightRepository.browse`, so scopes and the browser agree.
struct ExportRepository: Sendable {
    private let writer: any DatabaseWriter
    private let highlights: HighlightRepository

    init(database: AppDatabase) {
        self.writer = database.writer
        self.highlights = HighlightRepository(database: database)
    }

    // MARK: Content

    /// document → its title; tag → "#" + name; category → its name; themedReview → its name; all → "All highlights".
    /// A missing document, tag, category or themed review: `RepositoryError.notFound`.
    func scopeName(for scope: ExportScope) async throws -> String {
        try await writer.read { db in
            try Self.scopeName(for: scope, db)
        }
    }

    func content(for scope: ExportScope) async throws -> ExportContent {
        let (name, filter, alwaysIncludedDocumentId) = try await writer.read { db in
            let name = try Self.scopeName(for: scope, db)
            let filter = try Self.browseFilter(for: scope, db)
            return (name, filter, scope.kind == .document ? scope.id : nil)
        }
        let items = try await highlights.browse(filter: filter, sort: .documentPosition)
        let noteOnlyDocuments: NoteOnlyDocuments? = switch scope.kind {
        case .category: NoteOnlyDocuments(categoryId: scope.id)
        case .all: NoteOnlyDocuments(categoryId: nil)
        case .document, .tag, .themedReview: nil
        }
        return try await assemble(
            scopeName: name,
            items: items,
            extraDocumentId: alwaysIncludedDocumentId,
            noteOnlyDocuments: noteOnlyDocuments
        )
    }

    /// Only the given highlights (the one-off "Export selection"); documents that contribute at least one, with their notes.
    func content(forHighlightIds ids: [String], scopeName: String) async throws -> ExportContent {
        let wanted = Set(ids)
        let items = try await highlights.browse(filter: HighlightBrowserFilter(), sort: .documentPosition)
            .filter { wanted.contains($0.id) }
        return try await assemble(scopeName: scopeName, items: items, extraDocumentId: nil, noteOnlyDocuments: nil)
    }

    /// Emits when anything an export reads changes: highlight, highlightTag, tag, document, documentTag, documentNote
    /// or category. The value is a digest of the exported columns; the first element is the current value (T74).
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
            filter.tagIds = Set(review.filter.tagIds)
            filter.tagMode = review.filter.tagMode
            filter.documentIds = Set(review.filter.documentIds)
            filter.categoryIds = Set(review.filter.categoryIds)
            filter.colors = Set(review.filter.colors)
        }
        return filter
    }

    /// Documents without highlights that still belong in the export because they have a note.
    private struct NoteOnlyDocuments {
        /// nil: every document.
        var categoryId: String?
    }

    private func assemble(
        scopeName: String,
        items: [HighlightListItem],
        extraDocumentId: String?,
        noteOnlyDocuments: NoteOnlyDocuments?
    ) async throws -> ExportContent {
        let contributingIds = Set(items.map { $0.highlight.documentId })
        return try await writer.read { db in
            let categoryNames = Dictionary(
                uniqueKeysWithValues: try DocumentCategory.fetchAll(db).map { ($0.id, $0.name) }
            )
            let notes = try DocumentNote.fetchAll(db).reduce(into: [String: String]()) { result, note in
                let trimmed = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result[note.documentId] = trimmed }
            }

            var documentIds = contributingIds
            if let extraDocumentId { documentIds.insert(extraDocumentId) }
            if let noteOnlyDocuments {
                for documentId in notes.keys {
                    guard let categoryId = noteOnlyDocuments.categoryId else {
                        documentIds.insert(documentId)
                        continue
                    }
                    if let document = try LibraryDocument.fetchOne(db, key: documentId), document.categoryId == categoryId {
                        documentIds.insert(documentId)
                    }
                }
            }

            var byDocument: [String: [ExportHighlight]] = [:]
            for item in items {
                byDocument[item.highlight.documentId, default: []].append(Self.exportHighlight(item))
            }

            var documents: [ExportDocument] = []
            for documentId in documentIds {
                guard let document = try LibraryDocument.fetchOne(db, key: documentId) else { continue }
                let sorted = (byDocument[documentId] ?? []).sorted {
                    ($0.positionKey, $0.id) < ($1.positionKey, $1.id)
                }
                documents.append(ExportDocument(
                    id: document.id,
                    title: document.title,
                    author: document.author,
                    categoryName: categoryNames[document.categoryId] ?? "",
                    documentNote: notes[document.id],
                    highlights: sorted
                ))
            }
            documents.sort { left, right in
                let order = left.title.localizedStandardCompare(right.title)
                return order == .orderedSame ? left.id < right.id : order == .orderedAscending
            }
            return ExportContent(scopeName: scopeName, documents: documents)
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
