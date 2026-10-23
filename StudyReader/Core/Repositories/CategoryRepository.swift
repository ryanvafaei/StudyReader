import GRDB

/// Repository pattern for the rest of the data layer (ADR-0012): a `Sendable` struct over `AppDatabase`
/// with `async` reads and writes. Repositories are the only code that touches GRDB, besides `AppDatabase`
/// and migrations.
struct CategoryRepository: Sendable {
    private let writer: any DatabaseWriter

    init(database: AppDatabase) {
        self.writer = database.writer
    }

    /// Ordered by `sortOrder`, then `name`.
    func fetchAll() async throws -> [DocumentCategory] {
        try await writer.read { db in
            try DocumentCategory
                .order(Column("sortOrder").asc, Column("name").asc)
                .fetchAll(db)
        }
    }

    func fetch(id: String) async throws -> DocumentCategory? {
        try await writer.read { db in
            try DocumentCategory.fetchOne(db, key: id)
        }
    }

    /// Live list with the same ordering as `fetchAll()`. The first element is the current value.
    func observeAll() -> AsyncValueObservation<[DocumentCategory]> {
        ValueObservation
            .tracking { db in
                try DocumentCategory
                    .order(Column("sortOrder").asc, Column("name").asc)
                    .fetchAll(db)
            }
            .values(in: writer)
    }
}
