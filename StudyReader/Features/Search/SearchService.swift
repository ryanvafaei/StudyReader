import Foundation
import GRDB

/// Full-text search over document text, titles and authors, highlights, highlight notes and document notes
/// (SPEC F-12). Ranks with bm25 and returns `**`-marked snippets. User text only ever reaches SQLite as a bound
/// argument, already quoted by `SearchQueryParser`.
struct SearchService: Sendable {
    private let writer: any DatabaseWriter

    init(database: AppDatabase) {
        self.writer = database.writer
    }

    /// `SearchQueryParser.matchExpression(for: query)`; nil (empty, whitespace or exclusion-only input) gives empty
    /// results. `limit` applies per group. Within each group results are ordered by rank ascending, then id.
    /// FTS5 rejecting the expression (e.g. a NUL character in the input) also gives empty results.
    func search(_ query: String, filters: SearchFilters = SearchFilters(), limit: Int = 50) async throws -> SearchResults {
        guard limit > 0, let expression = SearchQueryParser.matchExpression(for: query) else {
            return SearchResults()
        }
        do {
            return try await writer.read { db in
                try Self.run(db, expression: expression, filters: filters, limit: limit)
            }
        } catch let error as DatabaseError where error.resultCode == .SQLITE_ERROR {
            Log.database.error("The search expression was rejected by FTS5.")
            return SearchResults()
        }
    }

    // MARK: - Queries

    private static func run(_ db: Database, expression: String, filters: SearchFilters, limit: Int) throws -> SearchResults {
        let textMatch = "{text editedText} : (\(expression))"
        let noteMatch = "note : (\(expression))"

        var documents = try documentTextHits(db, match: expression, filters: filters, limit: limit)
        documents += try titleAuthorHits(db, match: expression, filters: filters, limit: limit)
        documents.sort { ($0.rank, $0.id) < ($1.rank, $1.id) }

        var highlights = try highlightHits(db, match: textMatch, filters: filters, limit: limit)
        highlights.sort { ($0.rank, $0.id) < ($1.rank, $1.id) }

        var notes = try highlightNoteHits(db, match: noteMatch, filters: filters, limit: limit)
        notes += try documentNoteHits(db, match: expression, filters: filters, limit: limit)
        notes.sort { ($0.rank, $0.id) < ($1.rank, $1.id) }

        return SearchResults(
            documents: Array(documents.prefix(limit)),
            highlights: Array(highlights.prefix(limit)),
            notes: Array(notes.prefix(limit))
        )
    }

    /// `AND ...` clause plus its arguments for the filters on the document row `d`. `tagTable` is `documentTag`
    /// or, for highlight hits, `highlightTag` joined on the highlight row `h`.
    private static func filterClause(_ filters: SearchFilters, highlightTags: Bool) -> (sql: String, arguments: [any DatabaseValueConvertible]) {
        var parts: [String] = []
        var arguments: [any DatabaseValueConvertible] = []
        if let categoryId = filters.categoryId {
            parts.append("d.categoryId = ?")
            arguments.append(categoryId)
        }
        if let fileType = filters.fileType {
            parts.append("d.fileType = ?")
            arguments.append(fileType.rawValue)
        }
        if let tagId = filters.tagId {
            if highlightTags {
                parts.append("EXISTS (SELECT 1 FROM highlightTag x WHERE x.highlightId = h.id AND x.tagId = ?)")
            } else {
                parts.append("EXISTS (SELECT 1 FROM documentTag x WHERE x.documentId = d.id AND x.tagId = ?)")
            }
            arguments.append(tagId)
        }
        guard !parts.isEmpty else { return ("", arguments) }
        return (" AND " + parts.joined(separator: " AND "), arguments)
    }

    private static func arguments(match: String, filter: [any DatabaseValueConvertible], limit: Int) -> StatementArguments {
        var values: [(any DatabaseValueConvertible)?] = [match]
        for value in filter { values.append(value) }
        values.append(limit)
        return StatementArguments(values)
    }

    private static func documentTextHits(_ db: Database, match: String, filters: SearchFilters, limit: Int) throws -> [DocumentHit] {
        let filter = filterClause(filters, highlightTags: false)
        let sql = """
            SELECT dt.documentId AS documentId, d.title AS title, dt.unitIndex AS unitIndex,
                   snippet(documentText_fts, 0, '**', '**', '…', 12) AS snippet, bm25(documentText_fts) AS rank
            FROM documentText_fts
            JOIN documentText dt ON dt.rowid = documentText_fts.rowid
            JOIN document d ON d.id = dt.documentId
            WHERE documentText_fts MATCH ?\(filter.sql)
            ORDER BY rank, dt.documentId, dt.unitIndex LIMIT ?
            """
        let rows = try Row.fetchAll(db, sql: sql, arguments: arguments(match: match, filter: filter.arguments, limit: limit))
        return rows.map { row in
            DocumentHit(
                documentId: row["documentId"], title: row["title"], field: .text,
                unitIndex: row["unitIndex"], snippet: row["snippet"], rank: row["rank"]
            )
        }
    }

    private static func titleAuthorHits(_ db: Database, match: String, filters: SearchFilters, limit: Int) throws -> [DocumentHit] {
        let filter = filterClause(filters, highlightTags: false)
        let sql = """
            SELECT d.id AS documentId, d.title AS title,
                   snippet(document_fts, -1, '**', '**', '…', 12) AS snippet, bm25(document_fts) AS rank
            FROM document_fts
            JOIN document d ON d.rowid = document_fts.rowid
            WHERE document_fts MATCH ?\(filter.sql)
            ORDER BY rank, d.id LIMIT ?
            """
        let rows = try Row.fetchAll(db, sql: sql, arguments: arguments(match: match, filter: filter.arguments, limit: limit))
        return rows.map { row in
            DocumentHit(
                documentId: row["documentId"], title: row["title"], field: .titleOrAuthor,
                unitIndex: nil, snippet: row["snippet"], rank: row["rank"]
            )
        }
    }

    private static func highlightHits(_ db: Database, match: String, filters: SearchFilters, limit: Int) throws -> [HighlightHit] {
        let filter = filterClause(filters, highlightTags: true)
        let sql = """
            SELECT h.id AS highlightId, h.documentId AS documentId, d.title AS title, h.pageIndex AS pageIndex,
                   snippet(highlight_fts, -1, '**', '**', '…', 12) AS snippet, bm25(highlight_fts) AS rank
            FROM highlight_fts
            JOIN highlight h ON h.rowid = highlight_fts.rowid
            JOIN document d ON d.id = h.documentId
            WHERE highlight_fts MATCH ?\(filter.sql)
            ORDER BY rank, h.id LIMIT ?
            """
        let rows = try Row.fetchAll(db, sql: sql, arguments: arguments(match: match, filter: filter.arguments, limit: limit))
        return rows.map { row in
            HighlightHit(
                highlightId: row["highlightId"], documentId: row["documentId"], documentTitle: row["title"],
                pageIndex: row["pageIndex"], snippet: row["snippet"], rank: row["rank"]
            )
        }
    }

    private static func highlightNoteHits(_ db: Database, match: String, filters: SearchFilters, limit: Int) throws -> [NoteHit] {
        let filter = filterClause(filters, highlightTags: true)
        let sql = """
            SELECT h.id AS highlightId, h.documentId AS documentId, d.title AS title,
                   snippet(highlight_fts, 2, '**', '**', '…', 12) AS snippet, bm25(highlight_fts) AS rank
            FROM highlight_fts
            JOIN highlight h ON h.rowid = highlight_fts.rowid
            JOIN document d ON d.id = h.documentId
            WHERE highlight_fts MATCH ?\(filter.sql)
            ORDER BY rank, h.id LIMIT ?
            """
        let rows = try Row.fetchAll(db, sql: sql, arguments: arguments(match: match, filter: filter.arguments, limit: limit))
        return rows.map { row in
            NoteHit(
                kind: .highlightNote, documentId: row["documentId"], documentTitle: row["title"],
                highlightId: row["highlightId"], snippet: row["snippet"], rank: row["rank"]
            )
        }
    }

    private static func documentNoteHits(_ db: Database, match: String, filters: SearchFilters, limit: Int) throws -> [NoteHit] {
        let filter = filterClause(filters, highlightTags: false)
        let sql = """
            SELECT n.documentId AS documentId, d.title AS title,
                   snippet(documentNote_fts, 0, '**', '**', '…', 12) AS snippet, bm25(documentNote_fts) AS rank
            FROM documentNote_fts
            JOIN documentNote n ON n.rowid = documentNote_fts.rowid
            JOIN document d ON d.id = n.documentId
            WHERE documentNote_fts MATCH ?\(filter.sql)
            ORDER BY rank, n.documentId LIMIT ?
            """
        let rows = try Row.fetchAll(db, sql: sql, arguments: arguments(match: match, filter: filter.arguments, limit: limit))
        return rows.map { row in
            NoteHit(
                kind: .documentNote, documentId: row["documentId"], documentTitle: row["title"],
                highlightId: nil, snippet: row["snippet"], rank: row["rank"]
            )
        }
    }
}
