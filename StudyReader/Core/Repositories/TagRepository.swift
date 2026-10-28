import Foundation
import GRDB

enum TagError: Error, Equatable, LocalizedError {
    case invalidName, duplicateName, notFound

    var errorDescription: String? {
        switch self {
        case .invalidName: "Tag names need 1 to 40 characters."
        case .duplicateName: "A tag with this name already exists."
        case .notFound: "This tag no longer exists."
        }
    }
}

struct TagUsage: Sendable, Equatable, Identifiable {
    var tag: LibraryTag
    var highlightCount: Int
    var documentCount: Int
    var id: String { tag.id }
}

/// Tags on highlights and documents (SPEC F-10, ARCHITECTURE §4). A `Sendable` struct over `AppDatabase`
/// with `async` reads and writes (ADR-0012). Dedupe is by lookup, never by upsert or `OR IGNORE`.
struct TagRepository: Sendable {
    private static let maxNameLength = 40

    private let writer: any DatabaseWriter

    init(database: AppDatabase) {
        self.writer = database.writer
    }

    /// Trims whitespace, removes one leading "#", trims again. Valid: 1–40 Characters. Otherwise nil.
    static func normalizedName(_ raw: String) -> String? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            trimmed.removeFirst()
        }
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...maxNameLength).contains(trimmed.count) else { return nil }
        return trimmed
    }

    /// Lookup by name (the column is COLLATE NOCASE), else insert with the normalized name as typed.
    func findOrCreate(name: String, at date: Date) async throws -> LibraryTag {
        guard let normalized = Self.normalizedName(name) else { throw TagError.invalidName }
        return try await writer.write { db in
            if let existing = try Self.tag(named: normalized, db) {
                return existing
            }
            let tag = LibraryTag(id: UUID().uuidString, name: normalized, createdAt: date)
            try tag.insert(db)
            return tag
        }
    }

    /// Ordered by name (case-insensitive), then id.
    func fetchAll() async throws -> [LibraryTag] {
        try await writer.read { db in
            try Self.tags(db)
        }
    }

    /// Live list with the same ordering as `fetchAll()`. The first element is the current value.
    func observeAll() -> AsyncValueObservation<[LibraryTag]> {
        ValueObservation
            .tracking { db in
                try Self.tags(db)
            }
            .values(in: writer)
    }

    /// Tags in `fetchAll()` order with highlight and document counts (0 included).
    func observeUsage() -> AsyncValueObservation<[TagUsage]> {
        ValueObservation
            .tracking { db in
                let tags = try Self.tags(db)
                let highlightCounts = try Self.counts(
                    db,
                    sql: "SELECT tagId, COUNT(*) AS n FROM highlightTag GROUP BY tagId"
                )
                let documentCounts = try Self.counts(
                    db,
                    sql: "SELECT tagId, COUNT(*) AS n FROM documentTag GROUP BY tagId"
                )
                return tags.map { tag in
                    TagUsage(
                        tag: tag,
                        highlightCount: highlightCounts[tag.id] ?? 0,
                        documentCount: documentCounts[tag.id] ?? 0
                    )
                }
            }
            .values(in: writer)
    }

    /// Another tag with the same name (case-insensitive) → `.duplicateName`. The same tag in a different case is allowed.
    func rename(id: String, to name: String) async throws {
        guard let normalized = Self.normalizedName(name) else { throw TagError.invalidName }
        try await writer.write { db in
            guard var tag = try LibraryTag.fetchOne(db, key: id) else { throw TagError.notFound }
            if let other = try Self.tag(named: normalized, db), other.id != id {
                throw TagError.duplicateName
            }
            tag.name = normalized
            try tag.update(db, columns: ["name"])
        }
    }

    /// One transaction: every highlight and document linked to `sourceId` gets `targetId` (lookup, then insert,
    /// skipping existing links), then the source row is deleted and its links cascade. Same id → no-op.
    func merge(sourceId: String, into targetId: String) async throws {
        guard sourceId != targetId else { return }
        try await writer.write { db in
            guard try LibraryTag.fetchOne(db, key: sourceId) != nil,
                  try LibraryTag.fetchOne(db, key: targetId) != nil else {
                throw TagError.notFound
            }
            let highlightIds = try String.fetchAll(
                db,
                sql: "SELECT highlightId FROM highlightTag WHERE tagId = ?",
                arguments: [sourceId]
            )
            for highlightId in highlightIds where try !Self.highlightLinkExists(highlightId, tagId: targetId, db) {
                try HighlightTag(highlightId: highlightId, tagId: targetId).insert(db)
            }
            let documentIds = try String.fetchAll(
                db,
                sql: "SELECT documentId FROM documentTag WHERE tagId = ?",
                arguments: [sourceId]
            )
            for documentId in documentIds where try !Self.documentLinkExists(documentId, tagId: targetId, db) {
                try DocumentTag(documentId: documentId, tagId: targetId).insert(db)
            }
            try LibraryTag.deleteOne(db, key: sourceId)
        }
    }

    /// Deletes the tag; its links cascade. The highlights and documents stay.
    func delete(id: String) async throws {
        try await writer.write { db in
            guard try LibraryTag.deleteOne(db, key: id) else { throw TagError.notFound }
        }
    }

    /// Tags on the highlight, ordered by name then id.
    func tags(forHighlight highlightId: String) async throws -> [LibraryTag] {
        try await writer.read { db in
            try Self.tags(forHighlight: highlightId, db)
        }
    }

    /// Live version of `tags(forHighlight:)`. The first element is the current value.
    func observeTags(forHighlight highlightId: String) -> AsyncValueObservation<[LibraryTag]> {
        ValueObservation
            .tracking { db in
                try Self.tags(forHighlight: highlightId, db)
            }
            .values(in: writer)
    }

    /// Tag names of every highlight of the document that has at least one tag, keyed by highlight id, names sorted
    /// case-insensitively (same order as HighlightListItem.tagNames). One query.
    func tagNamesByHighlight(inDocument documentId: String) async throws -> [String: [String]] {
        try await writer.read { db in
            try Self.tagNamesByHighlight(inDocument: documentId, db)
        }
    }

    /// Live version of `tagNamesByHighlight(inDocument:)`. The first element is the current value.
    func observeTagNamesByHighlight(inDocument documentId: String) -> AsyncValueObservation<[String: [String]]> {
        ValueObservation
            .tracking { db in
                try Self.tagNamesByHighlight(inDocument: documentId, db)
            }
            .values(in: writer)
    }

    /// Replaces the highlight's tag set with exactly `tagIds` (duplicates ignored) in one transaction.
    func setTags(_ tagIds: [String], forHighlight highlightId: String) async throws {
        try await writer.write { db in
            try HighlightTag.filter(Column("highlightId") == highlightId).deleteAll(db)
            for tagId in Self.uniqueInOrder(tagIds) {
                try HighlightTag(highlightId: highlightId, tagId: tagId).insert(db)
            }
        }
    }

    /// Adds the tag to each highlight in one transaction. Existing links are skipped.
    func addTag(_ tagId: String, toHighlights highlightIds: [String]) async throws {
        try await writer.write { db in
            for highlightId in Self.uniqueInOrder(highlightIds)
            where try !Self.highlightLinkExists(highlightId, tagId: tagId, db) {
                try HighlightTag(highlightId: highlightId, tagId: tagId).insert(db)
            }
        }
    }

    /// Removes the tag from each listed highlight in one transaction. Missing links are ignored.
    func removeTag(_ tagId: String, fromHighlights highlightIds: [String]) async throws {
        try await writer.write { db in
            for highlightId in Self.uniqueInOrder(highlightIds) {
                _ = try HighlightTag.deleteOne(db, key: ["highlightId": highlightId, "tagId": tagId])
            }
        }
    }

    /// Tags on the document, ordered by name then id.
    func tags(forDocument documentId: String) async throws -> [LibraryTag] {
        try await writer.read { db in
            try Self.tags(forDocument: documentId, db)
        }
    }

    /// Live version of `tags(forDocument:)`. The first element is the current value.
    func observeTags(forDocument documentId: String) -> AsyncValueObservation<[LibraryTag]> {
        ValueObservation
            .tracking { db in
                try Self.tags(forDocument: documentId, db)
            }
            .values(in: writer)
    }

    /// Replaces the document's tag set with exactly `tagIds` (duplicates ignored) in one transaction.
    func setTags(_ tagIds: [String], forDocument documentId: String) async throws {
        try await writer.write { db in
            try DocumentTag.filter(Column("documentId") == documentId).deleteAll(db)
            for tagId in Self.uniqueInOrder(tagIds) {
                try DocumentTag(documentId: documentId, tagId: tagId).insert(db)
            }
        }
    }

    private static func tags(_ db: Database) throws -> [LibraryTag] {
        try LibraryTag
            .order(Column("name").collating(.nocase).asc, Column("id").asc)
            .fetchAll(db)
    }

    /// Lookup by name. The column is `COLLATE NOCASE`, so `==` compares case-insensitively.
    private static func tag(named name: String, _ db: Database) throws -> LibraryTag? {
        try LibraryTag.filter(Column("name") == name).fetchOne(db)
    }

    private static func tags(forHighlight highlightId: String, _ db: Database) throws -> [LibraryTag] {
        try LibraryTag.fetchAll(
            db,
            sql: """
                SELECT tag.* FROM tag
                JOIN highlightTag ON highlightTag.tagId = tag.id
                WHERE highlightTag.highlightId = ?
                ORDER BY tag.name COLLATE NOCASE, tag.id
                """,
            arguments: [highlightId]
        )
    }

    private static func tags(forDocument documentId: String, _ db: Database) throws -> [LibraryTag] {
        try LibraryTag.fetchAll(
            db,
            sql: """
                SELECT tag.* FROM tag
                JOIN documentTag ON documentTag.tagId = tag.id
                WHERE documentTag.documentId = ?
                ORDER BY tag.name COLLATE NOCASE, tag.id
                """,
            arguments: [documentId]
        )
    }

    private static func tagNamesByHighlight(inDocument documentId: String, _ db: Database) throws -> [String: [String]] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT ht.highlightId AS highlightId, t.name AS name
                FROM highlight h
                JOIN highlightTag ht ON ht.highlightId = h.id
                JOIN tag t ON t.id = ht.tagId
                WHERE h.documentId = ?
                """,
            arguments: [documentId]
        )
        var names: [String: [String]] = [:]
        for row in rows {
            let highlightId: String = row["highlightId"]
            names[highlightId, default: []].append(row["name"])
        }
        return names.mapValues { list in
            list.sorted { ($0.lowercased(), $0) < ($1.lowercased(), $1) }
        }
    }

    private static func highlightLinkExists(_ highlightId: String, tagId: String, _ db: Database) throws -> Bool {
        try HighlightTag.fetchOne(db, key: ["highlightId": highlightId, "tagId": tagId]) != nil
    }

    private static func documentLinkExists(_ documentId: String, tagId: String, _ db: Database) throws -> Bool {
        try DocumentTag.fetchOne(db, key: ["documentId": documentId, "tagId": tagId]) != nil
    }

    private static func counts(_ db: Database, sql: String) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for row in try Row.fetchAll(db, sql: sql) {
            let tagId: String = row["tagId"]
            let count: Int = row["n"]
            counts[tagId] = count
        }
        return counts
    }

    /// The ids with repeats removed, first occurrence kept.
    private static func uniqueInOrder(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}
