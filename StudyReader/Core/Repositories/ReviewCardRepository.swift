import Foundation
import GRDB

/// Errors from creating review cards through this repository (T99; T114 adds the Mastery cases).
enum ReviewCardError: Error, Equatable, LocalizedError {
    case notPassive

    var errorDescription: String? {
        switch self {
        case .notPassive: "Only passive cards can be created here."
        }
    }
}

/// `reviewCard` rows: reads, bulk passive-card creation and the automatic insert hook (SPEC F-15, F-17).
/// Suspension is never written here except through the inserts, which call `ReviewSuspension` after inserting
/// (ADR-0021). Inserts use `insert(db)` (ADR-0012).
struct ReviewCardRepository: Sendable {
    private let writer: any DatabaseWriter

    init(database: AppDatabase) {
        self.writer = database.writer
    }

    func fetch(id: String) async throws -> ReviewCard? {
        try await writer.read { db in
            try ReviewCard.fetchOne(db, key: id)
        }
    }

    /// The highlight's cards: passive first, then createdAt ASC, then id ASC.
    func cards(forHighlight highlightId: String) async throws -> [ReviewCard] {
        try await writer.read { db in
            try Self.forHighlight(highlightId, db)
        }
    }

    /// Live version of `cards(forHighlight:)`. The first element is the current value.
    func observeCards(forHighlight highlightId: String) -> AsyncValueObservation<[ReviewCard]> {
        ValueObservation
            .tracking { db in
                try Self.forHighlight(highlightId, db)
            }
            .values(in: writer)
    }

    /// SPEC F-17 bulk "Create review cards". One transaction. For each card (in order): skip it when its highlight
    /// doesn't exist or already has ANY review card (any type), else insert it. Then
    /// `ReviewSuspension.recompute(highlightIds:)` over the inserted highlights. Ignores the category's
    /// `autoCreateCards` (an explicit user action); an Off category makes the new card suspended (.frequencyOff).
    /// Every card must be passive, else `ReviewCardError.notPassive` (nothing written). Returns the number inserted.
    @discardableResult
    func insertPassiveCards(_ cards: [ReviewCard]) async throws -> Int {
        try await writer.write { db -> Int in
            guard cards.allSatisfy({ $0.cardType == .passive }) else {
                throw ReviewCardError.notPassive
            }
            var insertedHighlightIds: [String] = []
            for card in cards {
                guard try Highlight.fetchOne(db, key: card.highlightId) != nil else { continue }
                guard try Self.reviewCardCount(highlightId: card.highlightId, db) == 0 else { continue }
                try card.insert(db)
                insertedHighlightIds.append(card.highlightId)
            }
            try ReviewSuspension.recompute(highlightIds: insertedHighlightIds, db)
            return insertedHighlightIds.count
        }
    }

    /// One-time backfill for highlights made before cards existed (T129, ADR-0021). One transaction. For every
    /// highlight with no review card (any type), in createdAt then id order, builds a card with `makeCard` and inserts
    /// it through `insertAutomaticPassiveCard` (category rule and suspension included). Returns the number inserted.
    @discardableResult
    func backfillPassiveCards(_ makeCard: @Sendable (Highlight) throws -> ReviewCard) async throws -> Int {
        try await writer.write { db -> Int in
            let highlights = try Highlight.fetchAll(db, sql: """
                SELECT * FROM highlight
                WHERE id NOT IN (SELECT highlightId FROM reviewCard)
                ORDER BY createdAt, id
                """)
            var inserted = 0
            for highlight in highlights {
                if try Self.insertAutomaticPassiveCard(makeCard(highlight), db) {
                    inserted += 1
                }
            }
            return inserted
        }
    }

    /// For use INSIDE another repository's write (HighlightRepository.insert, T100). Inserts `card` only when
    /// `FrequencyPolicy.createsCardAutomatically(frequency:autoCreateCards:)` is true for the category of the card's
    /// highlight (highlight → document → category) and the highlight has no review card yet; then recomputes that
    /// highlight's suspension. Returns true when inserted. Not passive → `.notPassive`. Missing highlight → false.
    static func insertAutomaticPassiveCard(_ card: ReviewCard, _ db: Database) throws -> Bool {
        guard card.cardType == .passive else {
            throw ReviewCardError.notPassive
        }
        guard let highlight = try Highlight.fetchOne(db, key: card.highlightId),
              let document = try LibraryDocument.fetchOne(db, key: highlight.documentId),
              let category = try DocumentCategory.fetchOne(db, key: document.categoryId)
        else {
            return false
        }
        guard FrequencyPolicy.createsCardAutomatically(
            frequency: category.frequency,
            autoCreateCards: category.autoCreateCards
        ) else {
            return false
        }
        guard try reviewCardCount(highlightId: card.highlightId, db) == 0 else {
            return false
        }
        try card.insert(db)
        try ReviewSuspension.recompute(highlightIds: [card.highlightId], db)
        return true
    }

    /// Ordered: passive first, then createdAt ASC, then id ASC.
    private static func forHighlight(_ highlightId: String, _ db: Database) throws -> [ReviewCard] {
        let cards = try ReviewCard
            .filter(Column("highlightId") == highlightId)
            .order(Column("createdAt").asc, Column("id").asc)
            .fetchAll(db)
        return cards.filter { $0.cardType == .passive } + cards.filter { $0.cardType != .passive }
    }

    private static func reviewCardCount(highlightId: String, _ db: Database) throws -> Int {
        try ReviewCard.filter(Column("highlightId") == highlightId).fetchCount(db)
    }
}

/// Review queue reads and the rating write (T102). The SQL lives in `ReviewQueueSQL`; each method is one
/// `read` or `write` transaction.
extension ReviewCardRepository {
    /// One read: due and new candidates plus today's activity, from one snapshot.
    func dailyQueue(now: Date, dayStart: Date) async throws -> DailyQueueSnapshot {
        try await writer.read { db in
            try ReviewQueueSQL.dailyQueue(db, now: now, dayStart: dayStart)
        }
    }

    /// Live version of `dailyQueue`. Each run reads `now()` and the review day that contains it.
    func observeDailyQueue(now: any Now, calendar: Calendar) -> AsyncValueObservation<DailyQueueSnapshot> {
        ValueObservation
            .tracking { db in
                let current = now()
                return try ReviewQueueSQL.dailyQueue(
                    db,
                    now: current,
                    dayStart: ReviewDay.start(containing: current, calendar: calendar)
                )
            }
            .values(in: writer)
    }

    /// Items in the order of `cardIds`; ids without a card are skipped.
    func items(cardIds: [String]) async throws -> [ReviewCardItem] {
        try await writer.read { db in
            try ReviewQueueSQL.items(db, cardIds: cardIds)
        }
    }

    func item(cardId: String) async throws -> ReviewCardItem? {
        try await writer.read { db in
            try ReviewQueueSQL.item(db, cardId: cardId)
        }
    }

    /// One transaction: updates the card (`fsrsCard`, `dueAt`, `state`, and `introducedAt` when NULL) and inserts
    /// the log row. Missing card → `RepositoryError.notFound`, nothing written.
    @discardableResult
    func recordRating(_ write: RatingWrite) async throws -> ReviewLogEntry {
        try await writer.write { db in
            try ReviewQueueSQL.recordRating(db, write)
        }
    }

    /// Cards not suspended, state != new, dueAt < date.
    func dueCount(before date: Date) async throws -> Int {
        try await writer.read { db in
            try ReviewQueueSQL.dueCount(db, before: date)
        }
    }
}

/// The FSRS state after a frequency change (ReviewScheduler.rescheduledDue, T105).
struct RescheduledCard: Sendable, Equatable {
    var fsrsCard: String     // StoredFSRSCard JSON with the new due
    var dueAt: Date          // == its due
}

/// Card action writes (T103, SPEC F-18 "Change frequency").
extension ReviewCardRepository {
    /// One transaction: set frequencyOverride (nil clears it), and when `rescheduled` is non-nil also fsrsCard and dueAt,
    /// with update(db, columns:); then ReviewSuspension.recompute(highlightIds: [card.highlightId]). Missing card →
    /// RepositoryError.notFound.
    func updateFrequencyOverride(cardId: String, override: ReviewFrequency?, rescheduled: RescheduledCard?) async throws {
        try await writer.write { db in
            guard var card = try ReviewCard.fetchOne(db, key: cardId) else {
                throw RepositoryError.notFound
            }
            card.frequencyOverride = override
            var columns = ["frequencyOverride"]
            if let rescheduled {
                card.fsrsCard = rescheduled.fsrsCard
                card.dueAt = rescheduled.dueAt
                columns += ["fsrsCard", "dueAt"]
            }
            try card.update(db, columns: columns)
            try ReviewSuspension.recompute(highlightIds: [card.highlightId], db)
        }
    }
}
