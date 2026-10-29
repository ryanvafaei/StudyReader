import Foundation
import GRDB

/// SPEC F-17 card states. learning covers FSRS learning and relearning; suspended wins over the FSRS state.
enum FlashcardState: String, Sendable, CaseIterable {
    case new, learning, review, suspended
}

/// Filters for the Flashcards view (SPEC F-17). An empty set means "all"; the set fields combine with AND, and the
/// states and card types inside one field combine with OR. Highlight-side fields (documents, categories, tags) filter
/// the card's highlight. `dueFrom` is inclusive, `dueBefore` exclusive.
struct FlashcardFilter: Sendable, Equatable {
    var documentIds: Set<String> = []
    var categoryIds: Set<String> = []
    var tagIds: Set<String> = []
    var tagMode: TagMatchMode = .any
    var states: Set<FlashcardState> = []      // empty = all
    var cardTypes: Set<CardType> = []         // empty = all
    var dueFrom: Date? = nil                  // dueAt >= dueFrom
    var dueBefore: Date? = nil                // dueAt < dueBefore
}

/// One Flashcards row: the review card item plus its F-17 state and last review time.
struct FlashcardItem: Sendable, Equatable, Identifiable {
    var item: ReviewCardItem                  // T102 type (card, highlight, title, category frequency, tags)
    var state: FlashcardState
    var lastReviewedAt: Date?
    var id: String { item.id }
}

/// Builds the Flashcards SQL. Fixed SQL fragments only; every user value is a bound argument.
enum FlashcardSQL {
    /// Card ids with their state, in dueAt then id order; the full items come from `ReviewQueueSQL.items`.
    static func flashcards(_ db: Database, filter: FlashcardFilter) throws -> [FlashcardItem] {
        let where_ = whereClause(for: filter)
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT rc.id AS cardId, rc.state AS state, rc.suspended AS suspended, lr.lastReviewedAt AS lastReviewedAt
                FROM reviewCard rc
                JOIN highlight h ON h.id = rc.highlightId
                JOIN document d ON d.id = h.documentId
                LEFT JOIN (SELECT cardId, MAX(reviewedAt) AS lastReviewedAt FROM reviewLog GROUP BY cardId) lr
                    ON lr.cardId = rc.id
                WHERE \(where_.sql)
                ORDER BY rc.dueAt ASC, rc.id ASC
                """,
            arguments: StatementArguments(where_.arguments)
        )
        guard !rows.isEmpty else { return [] }

        var rowsById: [String: (state: FlashcardState, lastReviewedAt: Date?)] = [:]
        var ids: [String] = []
        for row in rows {
            let cardId: String = row["cardId"]
            let state: ReviewCardState = row["state"]
            let suspended: Bool = row["suspended"]
            let lastReviewedAt: Double? = row["lastReviewedAt"]
            ids.append(cardId)
            rowsById[cardId] = (
                flashcardState(state: state, suspended: suspended),
                lastReviewedAt.map { Date(timeIntervalSince1970: $0) }
            )
        }

        return try ReviewQueueSQL.items(db, cardIds: ids).compactMap { item in
            guard let row = rowsById[item.id] else { return nil }
            return FlashcardItem(item: item, state: row.state, lastReviewedAt: row.lastReviewedAt)
        }
    }

    /// The WHERE clause for `filter` (`1 = 1` when nothing is set). Clauses and arguments are appended in the same
    /// order, so the arguments line up with the markers.
    static func whereClause(for filter: FlashcardFilter) -> (sql: String, arguments: HighlightBrowseSQL.Arguments) {
        let highlightFilter = HighlightBrowserFilter(
            documentIds: filter.documentIds,
            categoryIds: filter.categoryIds,
            tagIds: filter.tagIds,
            tagMode: filter.tagMode
        )
        let highlightConditions = HighlightBrowseSQL.conditions(for: highlightFilter)
        var clauses: [String] = []
        var arguments: HighlightBrowseSQL.Arguments = []

        if highlightConditions.sql != "1 = 1" {
            clauses.append("(\(highlightConditions.sql))")
            arguments += highlightConditions.arguments
        }
        if !filter.states.isEmpty {
            let parts = FlashcardState.allCases.filter { filter.states.contains($0) }.map(stateClause)
            clauses.append("(\(parts.joined(separator: " OR ")))")
        }
        if !filter.cardTypes.isEmpty {
            let types = filter.cardTypes.map { $0.rawValue }.sorted()
            clauses.append("rc.cardType IN (\(placeholders(types.count)))")
            arguments += types.map { $0 as (any DatabaseValueConvertible)? }
        }
        if let dueFrom = filter.dueFrom {
            clauses.append("rc.dueAt >= ?")
            arguments.append(dueFrom.databaseUnixSeconds)
        }
        if let dueBefore = filter.dueBefore {
            clauses.append("rc.dueAt < ?")
            arguments.append(dueBefore.databaseUnixSeconds)
        }

        let sql = clauses.isEmpty ? "1 = 1" : clauses.joined(separator: " AND ")
        return (sql, arguments)
    }

    /// SQL for one F-17 state. Suspended wins over the FSRS state.
    private static func stateClause(_ state: FlashcardState) -> String {
        switch state {
        case .suspended: "rc.suspended = 1"
        case .new: "rc.suspended = 0 AND rc.state = 'new'"
        case .learning: "rc.suspended = 0 AND rc.state IN ('learning', 'relearning')"
        case .review: "rc.suspended = 0 AND rc.state = 'review'"
        }
    }

    private static func flashcardState(state: ReviewCardState, suspended: Bool) -> FlashcardState {
        if suspended { return .suspended }
        switch state {
        case .new: return .new
        case .learning, .relearning: return .learning
        case .review: return .review
        }
    }

    /// `n` bind markers, comma-separated. Callers pass n ≥ 1.
    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }
}
