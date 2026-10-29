import Foundation

enum ReviewCardFactoryError: Error, Equatable { case notMastery }

/// Builds new `ReviewCard` records. Pure: no database. Suspension is set by the repository.
enum ReviewCardFactory {
    /// A passive card for a highlight: state new, due now, not suspended.
    static func passive(highlightId: String, now: Date) throws -> ReviewCard {
        try make(highlightId: highlightId, cardType: .passive, clozeRanges: nil, question: nil, answer: nil, now: now)
    }

    /// A Mastery card (cloze or Q&A) with the given columns (T115 validates them). `.passive` throws `.notMastery`.
    static func mastery(highlightId: String, cardType: CardType, clozeRanges: [[Int]]?, question: String?,
                        answer: String?, now: Date) throws -> ReviewCard {
        guard cardType != .passive else { throw ReviewCardFactoryError.notMastery }
        return try make(highlightId: highlightId, cardType: cardType, clozeRanges: clozeRanges,
                        question: question, answer: answer, now: now)
    }

    private static func make(highlightId: String, cardType: CardType, clozeRanges: [[Int]]?, question: String?,
                             answer: String?, now: Date) throws -> ReviewCard {
        let rounded = now.storageRounded
        return ReviewCard(
            id: UUID().uuidString,
            highlightId: highlightId,
            cardType: cardType,
            clozeRanges: clozeRanges,
            question: question,
            answer: answer,
            fsrsCard: try StoredFSRSCard.new(due: now).json(),
            dueAt: rounded,
            state: .new,
            suspended: false,
            suspendedReason: nil,
            introducedAt: nil,
            createdAt: rounded
        )
    }
}
