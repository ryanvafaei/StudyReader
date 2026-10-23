import GRDB

/// Library documents. Phase 1 adds delete (with `FileStore` cleanup) and metadata updates.
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
}
