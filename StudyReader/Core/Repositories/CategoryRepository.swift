import Foundation
import GRDB

enum CategoryError: Error, Equatable, LocalizedError {
    case emptyName, nameTooLong, duplicateName, builtinCategory, notFound

    var errorDescription: String? {
        switch self {
        case .emptyName: "Enter a category name."
        case .nameTooLong: "Category names can have at most 40 characters."
        case .duplicateName: "A category with this name already exists."
        case .builtinCategory: "Built-in categories can't be renamed or deleted."
        case .notFound: "This category no longer exists."
        }
    }
}

struct CategoryUsage: Sendable, Equatable, Identifiable {
    var category: DocumentCategory
    var documentCount: Int
    var id: String { category.id }
}

/// Repository pattern for the rest of the data layer (ADR-0012): a `Sendable` struct over `AppDatabase`
/// with `async` reads and writes. Repositories are the only code that touches GRDB, besides `AppDatabase`
/// and migrations.
struct CategoryRepository: Sendable {
    private static let maxNameLength = 40

    private let writer: any DatabaseWriter

    init(database: AppDatabase) {
        self.writer = database.writer
    }

    /// Ordered by `sortOrder`, then `name`.
    func fetchAll() async throws -> [DocumentCategory] {
        try await writer.read { db in
            try Self.categories(db)
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
                try Self.categories(db)
            }
            .values(in: writer)
    }

    /// Trims; 1–40 characters. Duplicate = any existing name equal case-insensitively (lookup first, ADR-0012).
    /// New row: id UUID, custom, `frequency` normal, `autoCreateCards` true, `sortOrder` = max + 1.
    func create(name: String) async throws -> DocumentCategory {
        let trimmed = try Self.validatedName(name)
        return try await writer.write { db in
            try Self.requireUniqueName(trimmed, excludingId: nil, db)
            let maxSortOrder = try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM category") ?? -1
            let category = DocumentCategory(
                id: UUID().uuidString,
                name: trimmed,
                isBuiltin: false,
                frequency: .normal,
                autoCreateCards: true,
                sortOrder: maxSortOrder + 1
            )
            try category.insert(db)
            return category
        }
    }

    /// Custom categories only. Renaming to the same name with different case is allowed.
    func rename(id: String, to name: String) async throws {
        let trimmed = try Self.validatedName(name)
        try await writer.write { db in
            guard var category = try DocumentCategory.fetchOne(db, key: id) else {
                throw CategoryError.notFound
            }
            guard !category.isBuiltin else { throw CategoryError.builtinCategory }
            try Self.requireUniqueName(trimmed, excludingId: id, db)
            category.name = trimmed
            try category.update(db, columns: ["name"])
        }
    }

    /// Sets `frequency` and recomputes the suspension of every card in the category (ADR-0021), in one
    /// transaction. Returns the number of cards whose suspension changed.
    @discardableResult
    func setFrequency(id: String, _ frequency: ReviewFrequency) async throws -> Int {
        try await writer.write { db in
            guard var category = try DocumentCategory.fetchOne(db, key: id) else {
                throw CategoryError.notFound
            }
            category.frequency = frequency
            try category.update(db, columns: ["frequency"])
            return try ReviewSuspension.recompute(categoryId: id, db)
        }
    }

    /// Existing cards are untouched; the flag only affects new highlights (SPEC F-17).
    func setAutoCreateCards(id: String, _ enabled: Bool) async throws {
        try await writer.write { db in
            guard var category = try DocumentCategory.fetchOne(db, key: id) else {
                throw CategoryError.notFound
            }
            category.autoCreateCards = enabled
            try category.update(db, columns: ["autoCreateCards"])
        }
    }

    /// Custom categories only. One transaction: move its documents to `BuiltinCategory.other`, recompute
    /// the cards of the moved documents (ADR-0021), then delete the row. Returns the number of documents moved.
    @discardableResult
    func delete(id: String) async throws -> Int {
        try await writer.write { db in
            guard let category = try DocumentCategory.fetchOne(db, key: id) else {
                throw CategoryError.notFound
            }
            guard !category.isBuiltin else { throw CategoryError.builtinCategory }
            let movedIds = try LibraryDocument
                .filter(Column("categoryId") == id)
                .fetchAll(db)
                .map(\.id)
            let moved = try LibraryDocument
                .filter(Column("categoryId") == id)
                .updateAll(db, Column("categoryId").set(to: BuiltinCategory.other.id))
            try ReviewSuspension.recompute(documentIds: movedIds, db)
            try DocumentCategory.deleteOne(db, key: id)
            return moved
        }
    }

    /// Categories in `fetchAll()` order with document counts (0 included).
    func observeUsage() -> AsyncValueObservation<[CategoryUsage]> {
        ValueObservation
            .tracking { db in
                let categories = try Self.categories(db)
                var counts: [String: Int] = [:]
                for row in try Row.fetchAll(db, sql: "SELECT categoryId, COUNT(*) AS n FROM document GROUP BY categoryId") {
                    let categoryId: String = row["categoryId"]
                    let count: Int = row["n"]
                    counts[categoryId] = count
                }
                return categories.map { category in
                    CategoryUsage(category: category, documentCount: counts[category.id] ?? 0)
                }
            }
            .values(in: writer)
    }

    private static func categories(_ db: Database) throws -> [DocumentCategory] {
        try DocumentCategory
            .order(Column("sortOrder").asc, Column("name").asc)
            .fetchAll(db)
    }

    private static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CategoryError.emptyName }
        guard trimmed.count <= maxNameLength else { throw CategoryError.nameTooLong }
        return trimmed
    }

    /// `category.name` is `UNIQUE COLLATE NOCASE`, so `==` compares case-insensitively.
    private static func requireUniqueName(_ name: String, excludingId: String?, _ db: Database) throws {
        var request = DocumentCategory.filter(Column("name") == name)
        if let excludingId {
            request = request.filter(Column("id") != excludingId)
        }
        guard try request.fetchOne(db) == nil else { throw CategoryError.duplicateName }
    }
}
