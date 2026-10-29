import Foundation
import GRDB

/// Filters for the highlights browser (SPEC F-13). An empty set means "all"; the set fields combine with AND.
/// `tagMode` decides whether a highlight needs any or all of `tagIds`. Dates are inclusive from, exclusive before.
struct HighlightBrowserFilter: Sendable, Equatable {
    var documentIds: Set<String> = []
    var categoryIds: Set<String> = []
    var tagIds: Set<String> = []
    var tagMode: TagMatchMode = .any
    var colors: Set<HighlightColor> = []
    /// true: the note has text after trimming; false: the note is blank; nil: either.
    var hasNote: Bool? = nil
    var views: Set<ReaderViewKind> = []
    /// true: the highlight has at least one cloze or qa card; false: none; nil: either.
    var hasMastery: Bool? = nil
    var createdFrom: Date? = nil
    var createdBefore: Date? = nil
}

/// Sort orders for the highlights browser. Ties fall back to the highlight id, so the order is stable.
enum HighlightBrowserSort: String, Sendable, CaseIterable {
    /// createdAt DESC, id ASC
    case createdNewest
    /// document title COLLATE NOCASE ASC, documentId ASC, positionKey ASC, createdAt ASC, id ASC
    case documentPosition
    /// color ASC, createdAt DESC, id ASC
    case color
}

/// One browser row: the highlight with its document title, category and tags.
struct HighlightListItem: Sendable, Equatable, Identifiable {
    var highlight: Highlight
    var documentTitle: String
    var categoryId: String
    /// Tag ids, sorted.
    var tagIds: [String]
    /// Tag names, sorted case-insensitively.
    var tagNames: [String]
    /// Cloze and qa cards of this highlight (the Mastery badge).
    var masteryCardCount: Int = 0
    /// All review cards of this highlight, passive included.
    var reviewCardCount: Int = 0
    var id: String { highlight.id }
}

/// Builds the browse SQL. Only fixed SQL fragments are interpolated; every user value is a bound argument.
enum HighlightBrowseSQL {
    typealias Arguments = [(any DatabaseValueConvertible)?]

    /// A tag link of one highlight, read from the tag query.
    private struct TagPair: Sendable {
        let id: String
        let name: String
    }

    /// `onlyIds` nil: every highlight matching `filter`; non-nil: additionally `h.id IN (onlyIds)` (bound arguments;
    /// an empty set returns []).
    static func items(
        _ db: Database,
        filter: HighlightBrowserFilter,
        sort: HighlightBrowserSort,
        onlyIds: Set<String>? = nil
    ) throws -> [HighlightListItem] {
        if let onlyIds, onlyIds.isEmpty { return [] }
        let conditions = conditions(for: filter, onlyIds: onlyIds)
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT h.*, d.title AS documentTitle, d.categoryId AS categoryId,
                    (SELECT COUNT(*) FROM reviewCard r WHERE r.highlightId = h.id AND r.cardType IN ('cloze','qa'))
                        AS masteryCardCount,
                    (SELECT COUNT(*) FROM reviewCard r WHERE r.highlightId = h.id) AS reviewCardCount
                FROM highlight h
                JOIN document d ON d.id = h.documentId
                WHERE \(conditions.sql)
                ORDER BY \(orderBy(sort))
                """,
            arguments: StatementArguments(conditions.arguments)
        )
        guard !rows.isEmpty else { return [] }

        let tagRows = try Row.fetchAll(
            db,
            sql: """
                SELECT t.highlightId AS highlightId, g.id AS tagId, g.name AS tagName
                FROM highlightTag t
                JOIN tag g ON g.id = t.tagId
                WHERE t.highlightId IN (
                    SELECT h.id FROM highlight h
                    JOIN document d ON d.id = h.documentId
                    WHERE \(conditions.sql)
                )
                """,
            arguments: StatementArguments(conditions.arguments)
        )
        var tagsByHighlight: [String: [TagPair]] = [:]
        for row in tagRows {
            let highlightId: String = row["highlightId"]
            tagsByHighlight[highlightId, default: []].append(TagPair(id: row["tagId"], name: row["tagName"]))
        }

        return try rows.map { row in
            let highlight = try Highlight(row: row)
            let tags = tagsByHighlight[highlight.id] ?? []
            let masteryCardCount: Int = row["masteryCardCount"]
            let reviewCardCount: Int = row["reviewCardCount"]
            return HighlightListItem(
                highlight: highlight,
                documentTitle: row["documentTitle"],
                categoryId: row["categoryId"],
                tagIds: tags.map { $0.id }.sorted(),
                tagNames: tags.map { $0.name }.sorted { ($0.lowercased(), $0) < ($1.lowercased(), $1) },
                masteryCardCount: masteryCardCount,
                reviewCardCount: reviewCardCount
            )
        }
    }

    /// The WHERE clause (`1 = 1` when nothing is set) and its arguments, for the highlight alias `h` and document alias `d`.
    static func conditions(
        for filter: HighlightBrowserFilter,
        onlyIds: Set<String>? = nil
    ) -> (sql: String, arguments: Arguments) {
        var clauses: [String] = []
        var arguments: Arguments = []

        if !filter.documentIds.isEmpty {
            let ids = filter.documentIds.sorted()
            clauses.append("h.documentId IN (\(placeholders(ids.count)))")
            arguments += ids.map { $0 as (any DatabaseValueConvertible)? }
        }
        if !filter.categoryIds.isEmpty {
            let ids = filter.categoryIds.sorted()
            clauses.append("d.categoryId IN (\(placeholders(ids.count)))")
            arguments += ids.map { $0 as (any DatabaseValueConvertible)? }
        }
        if !filter.tagIds.isEmpty {
            let ids = filter.tagIds.sorted()
            switch filter.tagMode {
            case .any:
                clauses.append("""
                    EXISTS (SELECT 1 FROM highlightTag t WHERE t.highlightId = h.id AND t.tagId IN (\(placeholders(ids.count))))
                    """)
                arguments += ids.map { $0 as (any DatabaseValueConvertible)? }
            case .all:
                clauses.append("""
                    (SELECT COUNT(DISTINCT t.tagId) FROM highlightTag t \
                    WHERE t.highlightId = h.id AND t.tagId IN (\(placeholders(ids.count)))) = ?
                    """)
                arguments += ids.map { $0 as (any DatabaseValueConvertible)? }
                arguments.append(ids.count)
            }
        }
        if !filter.colors.isEmpty {
            let colors = filter.colors.map { $0.rawValue }.sorted()
            clauses.append("h.color IN (\(placeholders(colors.count)))")
            arguments += colors.map { $0 as (any DatabaseValueConvertible)? }
        }
        if let hasNote = filter.hasNote {
            clauses.append(hasNote ? "TRIM(h.note) <> ''" : "TRIM(h.note) = ''")
        }
        if !filter.views.isEmpty {
            let views = filter.views.map { $0.rawValue }.sorted()
            clauses.append("h.view IN (\(placeholders(views.count)))")
            arguments += views.map { $0 as (any DatabaseValueConvertible)? }
        }
        if let hasMastery = filter.hasMastery {
            clauses.append(hasMastery
                ? "EXISTS (SELECT 1 FROM reviewCard r WHERE r.highlightId = h.id AND r.cardType IN ('cloze','qa'))"
                : "NOT EXISTS (SELECT 1 FROM reviewCard r WHERE r.highlightId = h.id AND r.cardType IN ('cloze','qa'))")
        }
        if let createdFrom = filter.createdFrom {
            clauses.append("h.createdAt >= ?")
            arguments.append(createdFrom.databaseUnixSeconds)
        }
        if let createdBefore = filter.createdBefore {
            clauses.append("h.createdAt < ?")
            arguments.append(createdBefore.databaseUnixSeconds)
        }
        if let onlyIds, !onlyIds.isEmpty {
            let ids = onlyIds.sorted()
            clauses.append("h.id IN (\(placeholders(ids.count)))")
            arguments += ids.map { $0 as (any DatabaseValueConvertible)? }
        }

        let sql = clauses.isEmpty ? "1 = 1" : clauses.joined(separator: " AND ")
        return (sql, arguments)
    }

    private static func orderBy(_ sort: HighlightBrowserSort) -> String {
        switch sort {
        case .createdNewest:
            "h.createdAt DESC, h.id ASC"
        case .documentPosition:
            "d.title COLLATE NOCASE ASC, h.documentId ASC, h.positionKey ASC, h.createdAt ASC, h.id ASC"
        case .color:
            "h.color ASC, h.createdAt DESC, h.id ASC"
        }
    }

    /// `n` bind markers, comma-separated. Callers pass n ≥ 1.
    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }
}
