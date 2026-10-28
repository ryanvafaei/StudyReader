import Foundation
import GRDB

/// Full-text search over document text, titles and authors, highlights, highlight notes and document notes
/// (SPEC F-12). Ranks with bm25 and returns `**`-marked snippets. User text only ever reaches SQLite as a bound
/// argument, already quoted by `SearchQueryParser`. It reads the FTS tables directly, like a repository; it is the
/// only search code that touches GRDB.
struct SearchService: Sendable {
    private let writer: any DatabaseWriter

    init(database: AppDatabase) {
        self.writer = database.writer
    }

    /// `SearchQueryParser.matchExpression(for: query)`; nil (empty, whitespace or exclusion-only input) gives empty
    /// results. `limit` applies per group. Within each group results are ordered by rank ascending, then by numeric
    /// keys (document, field, unit; highlight id; note kind, then highlight or document). FTS5 syntax errors give
    /// empty results; every other database error is thrown.
    func search(_ query: String, filters: SearchFilters = SearchFilters(), limit: Int = 50) async throws -> SearchResults {
        guard limit > 0, let parts = SearchQueryParser.matchParts(for: query) else {
            return SearchResults()
        }
        do {
            return try await writer.read { db in
                try Self.run(db, parts: parts, filters: filters, limit: limit)
            }
        } catch let error as DatabaseError where error.resultCode == .SQLITE_ERROR && error.message?.hasPrefix("fts5:") == true {
            let message = error.message ?? ""
            Log.database.error("FTS5 rejected the search expression: \(message, privacy: .private)")
            return SearchResults()
        }
    }

    // MARK: - Queries

    private static func run(_ db: Database, parts: SearchQueryParser.MatchParts, filters: SearchFilters, limit: Int) throws -> SearchResults {
        let expression = parts.negated.map { "(\(parts.positive)) NOT (\($0))" } ?? "(\(parts.positive))"
        let textMatch = scoped(parts, positive: "{text editedText}", negative: "{text editedText note}")
        let noteMatch = scoped(parts, positive: "note", negative: "note")

        var documents = try documentTextHits(db, match: expression, filters: filters, limit: limit)
        documents += try titleAuthorHits(db, match: expression, filters: filters, limit: limit)
        documents.sort {
            ($0.rank, $0.documentId, $0.field.rawValue, $0.unitIndex ?? -1)
                < ($1.rank, $1.documentId, $1.field.rawValue, $1.unitIndex ?? -1)
        }

        var highlights = try highlightHits(db, match: textMatch, filters: filters, limit: limit)
        highlights.sort { ($0.rank, $0.highlightId) < ($1.rank, $1.highlightId) }

        var notes = try highlightNoteHits(db, match: noteMatch, filters: filters, limit: limit)
        notes += try documentNoteHits(db, match: expression, filters: filters, limit: limit)
        notes.sort {
            ($0.rank, $0.kind.rawValue, $0.highlightId ?? $0.documentId)
                < ($1.rank, $1.kind.rawValue, $1.highlightId ?? $1.documentId)
        }

        return SearchResults(
            documents: Array(documents.prefix(limit)),
            highlights: Array(highlights.prefix(limit)),
            notes: Array(notes.prefix(limit))
        )
    }

    /// The positive terms restricted to the `positive` columns, minus any row where a negated term matches in the
    /// `negative` columns. A negated term that appears in another column of the same row (e.g. a highlight's note
    /// for a term that is in its text) still excludes that row, which a single column-filtered NOT would miss.
    private static func scoped(_ parts: SearchQueryParser.MatchParts, positive: String, negative: String) -> String {
        let match = "\(positive) : (\(parts.positive))"
        guard let negated = parts.negated else { return "(\(match))" }
        return "(\(match)) NOT (\(negative) : (\(negated)))"
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
            SELECT dt.documentId AS documentId, d.title AS title, d.fileType AS fileType, dt.unitIndex AS unitIndex,
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
                unitIndex: row["unitIndex"], snippet: row["snippet"], rank: row["rank"],
                fileType: row["fileType"]
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
