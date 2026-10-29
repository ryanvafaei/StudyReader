import Foundation
import GRDB

enum DocumentEditError: Error, Equatable, LocalizedError {
    case emptyTitle

    var errorDescription: String? {
        switch self {
        case .emptyTitle: "A title is required."
        }
    }
}

/// Library documents. Frequent non-text saves use column-limited `update(db, columns:)` so the FTS
/// triggers don't re-index (ADR-0013).
struct DocumentRepository: Sendable {
    private let writer: any DatabaseWriter

    init(database: AppDatabase) {
        self.writer = database.writer
    }

    /// Throws `DatabaseError` on constraint violations (e.g. duplicate `fileHash`).
    func insert(_ document: LibraryDocument) async throws {
        try await writer.write { db in
            try document.insert(db)
        }
    }

    func fetch(id: String) async throws -> LibraryDocument? {
        try await writer.read { db in
            try LibraryDocument.fetchOne(db, key: id)
        }
    }

    func fetch(fileHash: String) async throws -> LibraryDocument? {
        try await writer.read { db in
            try LibraryDocument
                .filter(Column("fileHash") == fileHash)
                .fetchOne(db)
        }
    }

    /// Newest first (SPEC F-01 default sort), then `title`.
    func fetchAll() async throws -> [LibraryDocument] {
        try await writer.read { db in
            try LibraryDocument
                .order(Column("addedAt").desc, Column("title").asc)
                .fetchAll(db)
        }
    }

    /// Live list with the same ordering as `fetchAll()`. The first element is the current value.
    func observeAll() -> AsyncValueObservation<[LibraryDocument]> {
        ValueObservation
            .tracking { db in
                try LibraryDocument
                    .order(Column("addedAt").desc, Column("title").asc)
                    .fetchAll(db)
            }
            .values(in: writer)
    }

    /// The library list rows (SPEC F-01), in `fetchAll()` order.
    func fetchAllItems() async throws -> [LibraryItem] {
        try await writer.read { db in
            try Self.items(db)
        }
    }

    /// Live version of `fetchAllItems()`. The first element is the current value.
    func observeItems() -> AsyncValueObservation<[LibraryItem]> {
        ValueObservation
            .tracking { db in
                try Self.items(db)
            }
            .values(in: writer)
    }

    /// Deletes the row in one transaction; SQL cascades remove dependent rows and FTS entries through
    /// triggers. Then removes `Documents/<id>/`. Returns false when no row existed (the folder is still removed).
    @discardableResult
    func delete(id: String, fileStore: FileStore) async throws -> Bool {
        let deleted = try await writer.write { db in
            try LibraryDocument.deleteOne(db, key: id)
        }
        try fileStore.deleteDocumentFolder(documentId: id)
        return deleted
    }

    /// Title and author are trimmed; an empty title throws `DocumentEditError.emptyTitle`. A changed category
    /// recomputes the document's cards in the same write (ADR-0021).
    func updateMetadata(id: String, title: String, author: String, categoryId: String) async throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw DocumentEditError.emptyTitle }
        try await writer.write { db in
            guard var document = try LibraryDocument.fetchOne(db, key: id) else {
                throw RepositoryError.notFound
            }
            let categoryChanged = document.categoryId != categoryId
            document.title = trimmedTitle
            document.author = trimmedAuthor
            document.categoryId = categoryId
            try document.update(db, columns: ["title", "author", "categoryId"])
            if categoryChanged {
                try ReviewSuspension.recompute(documentIds: [id], db)
            }
        }
    }

    func updateCover(id: String, coverPath: String?, coverSource: CoverSource) async throws {
        try await update(id: id, columns: ["coverPath", "coverSource"]) { document in
            document.coverPath = coverPath
            document.coverSource = coverSource
        }
    }

    /// `progress` is clamped to 0...1.
    func updatePDFPosition(id: String, position: PDFPosition, progress: Double) async throws {
        let clamped = Self.clampedProgress(progress)
        try await update(id: id, columns: ["pdfPosition", "progress"]) { document in
            document.pdfPosition = position
            document.progress = clamped
        }
    }

    /// `progress` is clamped to 0...1.
    func updateTextPosition(id: String, offset: Int, progress: Double) async throws {
        let clamped = Self.clampedProgress(progress)
        try await update(id: id, columns: ["textPosition", "progress"]) { document in
            document.textPosition = offset
            document.progress = clamped
        }
    }

    func markOpened(id: String, at date: Date) async throws {
        try await update(id: id, columns: ["lastOpenedAt"]) { document in
            document.lastOpenedAt = date
        }
    }

    func updateExtraction(id: String, status: ExtractionStatus, version: Int) async throws {
        try await update(id: id, columns: ["extractionStatus", "extractionVersion"]) { document in
            document.extractionStatus = status
            document.extractionVersion = version
        }
    }

    /// Fetches the row and updates only `columns` in the same write. Missing row: `RepositoryError.notFound`.
    private func update(
        id: String,
        columns: [String],
        _ change: @escaping @Sendable (inout LibraryDocument) -> Void
    ) async throws {
        try await writer.write { db in
            guard var document = try LibraryDocument.fetchOne(db, key: id) else {
                throw RepositoryError.notFound
            }
            change(&document)
            try document.update(db, columns: columns)
        }
    }

    private static func clampedProgress(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }

    /// Shared by `fetchAllItems()` and `observeItems()`. Runs inside one read.
    private static func items(_ db: Database) throws -> [LibraryItem] {
        let documents = try LibraryDocument
            .order(Column("addedAt").desc, Column("title").asc)
            .fetchAll(db)
        let categoryNames = Dictionary(
            try DocumentCategory.fetchAll(db).map { ($0.id, $0.name) },
            uniquingKeysWith: { _, last in last }
        )
        var highlightCounts: [String: Int] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT documentId, COUNT(*) AS n FROM highlight GROUP BY documentId") {
            let documentId: String = row["documentId"]
            let count: Int = row["n"]
            highlightCounts[documentId] = count
        }
        var tagIds: [String: [String]] = [:]
        for link in try DocumentTag.order(Column("tagId").asc).fetchAll(db) {
            tagIds[link.documentId, default: []].append(link.tagId)
        }
        return documents.map { document in
            LibraryItem(
                document: document,
                categoryName: categoryNames[document.categoryId] ?? "",
                highlightCount: highlightCounts[document.id] ?? 0,
                tagIds: tagIds[document.id] ?? []
            )
        }
    }
}
