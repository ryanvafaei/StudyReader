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
