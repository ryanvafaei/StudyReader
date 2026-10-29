import Foundation
import GRDB

/// One card row for the session builders. No highlight text (T102).
struct ReviewQueueEntry: Sendable, Equatable, Identifiable {
    var cardId: String
    var highlightId: String
    var cardType: CardType
    var state: ReviewCardState
    var dueAt: Date
    var introducedAt: Date?
    var highlightCreatedAt: Date
    /// MAX(reviewLog.reviewedAt) of this card, nil if never rated.
    var lastReviewedAt: Date?
    var id: String { cardId }
}

/// What happened since the start of the current review day.
struct ReviewDayActivity: Sendable, Equatable {
    var ratedCardIds: Set<String> = []          // any session kind, reviewedAt >= dayStart
    var dailyRatedCardIds: Set<String> = []     // sessionKind 'daily', reviewedAt >= dayStart
    var themedRatedCardIds: Set<String> = []    // sessionKind 'themed', reviewedAt >= dayStart
    var introducedCardIds: Set<String> = []     // introducedAt >= dayStart
}

struct DailyQueueSnapshot: Sendable, Equatable {
    /// Not suspended, state != new, dueAt <= now. Ordered dueAt ASC, cardId ASC.
    var due: [ReviewQueueEntry]
    /// Not suspended, state == new, introducedAt IS NULL. Ordered highlight createdAt ASC, cardId ASC.
    var new: [ReviewQueueEntry]
    var activity: ReviewDayActivity
}

/// One card with what the review screen shows.
struct ReviewCardItem: Sendable, Equatable, Identifiable {
    var card: ReviewCard
    var highlight: Highlight
    var documentTitle: String
    var categoryFrequency: ReviewFrequency
    /// Sorted case-insensitively (same order as HighlightListItem.tagNames).
    var tagNames: [String]
    var id: String { card.id }
}

/// Everything one rating writes (built by ReviewService, T105).
struct RatingWrite: Sendable, Equatable {
    var cardId: String
    var fsrsCard: String            // StoredFSRSCard JSON after the review
    var dueAt: Date                 // == that card's due (storage-rounded)
    var state: ReviewCardState
    var reviewedAt: Date
    var rating: ReviewRating
    var sessionKind: ReviewSessionKind
    var themedReviewId: String?     // non-nil only for .themed
    var fsrsLog: String             // StoredFSRSLog JSON
}

/// Builds the review queue SQL. Only fixed SQL is written here; every date is a bound `databaseUnixSeconds` value.
enum ReviewQueueSQL {
    /// Shared select list for queue rows: `rc` = reviewCard, `h` = highlight, `lr` = last review per card.
    private static let entryColumns = """
        rc.id AS cardId, rc.highlightId AS highlightId, rc.cardType AS cardType, rc.state AS state,
        rc.dueAt AS dueAt, rc.introducedAt AS introducedAt, h.createdAt AS highlightCreatedAt,
        lr.lastReviewedAt AS lastReviewedAt
        """

    private static let entryJoins = """
        JOIN highlight h ON h.id = rc.highlightId
        LEFT JOIN (SELECT cardId, MAX(reviewedAt) AS lastReviewedAt FROM reviewLog GROUP BY cardId) lr
            ON lr.cardId = rc.id
        """

    /// Due and new candidates plus today's activity, all read from the same database snapshot.
    static func dailyQueue(_ db: Database, now: Date, dayStart: Date) throws -> DailyQueueSnapshot {
        let due = try Row.fetchAll(
            db,
            sql: """
                SELECT \(entryColumns)
                FROM reviewCard rc
                \(entryJoins)
                WHERE rc.suspended = 0 AND rc.state <> 'new' AND rc.dueAt <= ?
                ORDER BY rc.dueAt ASC, rc.id ASC
                """,
            arguments: [now.databaseUnixSeconds]
        ).map(entry)

        let new = try Row.fetchAll(
            db,
            sql: """
                SELECT \(entryColumns)
                FROM reviewCard rc
                \(entryJoins)
                WHERE rc.suspended = 0 AND rc.state = 'new' AND rc.introducedAt IS NULL
                ORDER BY h.createdAt ASC, rc.id ASC
                """
        ).map(entry)

        return DailyQueueSnapshot(
            due: due,
            new: new,
            activity: try activity(db, dayStart: dayStart)
        )
    }

    /// Cards rated or introduced since `dayStart`, split by session kind.
    static func activity(_ db: Database, dayStart: Date) throws -> ReviewDayActivity {
        var activity = ReviewDayActivity()
        let rated = try Row.fetchAll(
            db,
            sql: "SELECT DISTINCT cardId, sessionKind FROM reviewLog WHERE reviewedAt >= ?",
            arguments: [dayStart.databaseUnixSeconds]
        )
        for row in rated {
            let cardId: String = row["cardId"]
            let kind: ReviewSessionKind = row["sessionKind"]
            activity.ratedCardIds.insert(cardId)
            switch kind {
            case .daily: activity.dailyRatedCardIds.insert(cardId)
            case .themed: activity.themedRatedCardIds.insert(cardId)
            }
        }
        let introduced = try String.fetchAll(
            db,
            sql: "SELECT id FROM reviewCard WHERE introducedAt >= ?",
            arguments: [dayStart.databaseUnixSeconds]
        )
        activity.introducedCardIds = Set(introduced)
        return activity
    }

    /// Full items in the order of `cardIds`. Ids without a card are skipped; repeated ids appear once.
    static func items(_ db: Database, cardIds: [String]) throws -> [ReviewCardItem] {
        let ids = uniqueInOrder(cardIds)
        guard !ids.isEmpty else { return [] }

        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT rc.*, d.title AS documentTitle, c.frequency AS categoryFrequency
                FROM reviewCard rc
                JOIN highlight h ON h.id = rc.highlightId
                JOIN document d ON d.id = h.documentId
                JOIN category c ON c.id = d.categoryId
                WHERE rc.id IN (\(placeholders(ids.count)))
                """,
            arguments: StatementArguments(ids.map { $0 as (any DatabaseValueConvertible)? })
        )
        guard !rows.isEmpty else { return [] }

        var cardsById: [String: (card: ReviewCard, row: Row)] = [:]
        for row in rows {
            let card = try ReviewCard(row: row)
            cardsById[card.id] = (card, row)
        }

        let highlightIds = Array(Set(cardsById.values.map { $0.card.highlightId })).sorted()
        let highlights = try Highlight.filter(keys: highlightIds).fetchAll(db)
        let highlightsById = Dictionary(uniqueKeysWithValues: highlights.map { ($0.id, $0) })

        let tagRows = try Row.fetchAll(
            db,
            sql: """
                SELECT t.highlightId AS highlightId, g.name AS tagName
                FROM highlightTag t
                JOIN tag g ON g.id = t.tagId
                WHERE t.highlightId IN (\(placeholders(highlightIds.count)))
                """,
            arguments: StatementArguments(highlightIds.map { $0 as (any DatabaseValueConvertible)? })
        )
        var tagNamesByHighlight: [String: [String]] = [:]
        for row in tagRows {
            let highlightId: String = row["highlightId"]
            let name: String = row["tagName"]
            tagNamesByHighlight[highlightId, default: []].append(name)
        }

        return try ids.compactMap { id in
            guard let found = cardsById[id] else { return nil }
            let card = found.card
            guard let highlight = highlightsById[card.highlightId] else { return nil }
            let names = tagNamesByHighlight[card.highlightId] ?? []
            let categoryFrequency: ReviewFrequency = found.row["categoryFrequency"]
            let documentTitle: String = found.row["documentTitle"]
            return ReviewCardItem(
                card: card,
                highlight: highlight,
                documentTitle: documentTitle,
                categoryFrequency: categoryFrequency,
                tagNames: names.sorted { ($0.lowercased(), $0) < ($1.lowercased(), $1) }
            )
        }
    }

    static func item(_ db: Database, cardId: String) throws -> ReviewCardItem? {
        try items(db, cardIds: [cardId]).first
    }

    /// Writes one rating: updates the card, inserts the log row, sets `introducedAt` only when it is NULL.
    /// Missing card → `RepositoryError.notFound` before anything is written. Dates are stored storage-rounded.
    static func recordRating(_ db: Database, _ write: RatingWrite) throws -> ReviewLogEntry {
        guard var card = try ReviewCard.fetchOne(db, key: write.cardId) else {
            throw RepositoryError.notFound
        }
        let reviewedAt = write.reviewedAt.storageRounded
        card.fsrsCard = write.fsrsCard
        card.dueAt = write.dueAt.storageRounded
        card.state = write.state
        var columns = ["fsrsCard", "dueAt", "state"]
        if card.introducedAt == nil {
            card.introducedAt = reviewedAt
            columns.append("introducedAt")
        }
        try card.update(db, columns: columns)

        let entry = ReviewLogEntry(
            id: UUID().uuidString,
            cardId: write.cardId,
            rating: write.rating.rawValue,
            reviewedAt: reviewedAt,
            sessionKind: write.sessionKind,
            themedReviewId: write.themedReviewId,
            fsrsLog: write.fsrsLog
        )
        try entry.insert(db)
        return entry
    }

    /// Cards not suspended, state != new, dueAt < date.
    static func dueCount(_ db: Database, before date: Date) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM reviewCard WHERE suspended = 0 AND state <> 'new' AND dueAt < ?",
            arguments: [date.databaseUnixSeconds]
        ) ?? 0
    }

    /// Maps a queue row. GRDB's default Date decoding differs from the record strategies, so dates are read as Doubles.
    private static func entry(_ row: Row) -> ReviewQueueEntry {
        let dueAt: Double = row["dueAt"]
        let introducedAt: Double? = row["introducedAt"]
        let highlightCreatedAt: Double = row["highlightCreatedAt"]
        let lastReviewedAt: Double? = row["lastReviewedAt"]
        return ReviewQueueEntry(
            cardId: row["cardId"],
            highlightId: row["highlightId"],
            cardType: row["cardType"],
            state: row["state"],
            dueAt: Date(timeIntervalSince1970: dueAt),
            introducedAt: introducedAt.map { Date(timeIntervalSince1970: $0) },
            highlightCreatedAt: Date(timeIntervalSince1970: highlightCreatedAt),
            lastReviewedAt: lastReviewedAt.map { Date(timeIntervalSince1970: $0) }
        )
    }

    /// `n` bind markers, comma-separated. Callers pass n ≥ 1.
    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private static func uniqueInOrder(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}
