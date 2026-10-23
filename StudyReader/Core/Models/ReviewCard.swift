import Foundation

/// `reviewCard` table (ARCHITECTURE §4). `clozeRanges` is a JSON column; `fsrsCard` is a JSON string
/// owned by the review engine (Phase 2), so it stays a plain `String` here.
struct ReviewCard: StudyRecord, Equatable, Identifiable {
    static let databaseTableName = "reviewCard"

    var id: String
    var highlightId: String
    var cardType: CardType
    var clozeRanges: [[Int]]? = nil
    var question: String? = nil
    var answer: String? = nil
    var fsrsCard: String
    var dueAt: Date
    var state: CardState
    var frequencyOverride: ReviewFrequency? = nil
    var suspended: Bool = false
    var suspendedReason: SuspendedReason? = nil
    var introducedAt: Date? = nil
    var createdAt: Date
}

/// `reviewLog` table (ARCHITECTURE §4). Swift name `ReviewLogEntry` avoids the `FSRS.ReviewLog` clash (ADR-0012).
struct ReviewLogEntry: StudyRecord, Equatable, Identifiable {
    static let databaseTableName = "reviewLog"

    var id: String
    var cardId: String
    var rating: Int                          // FSRS Rating raw value
    var reviewedAt: Date
    var sessionKind: ReviewSessionKind
    var themedReviewId: String? = nil
    var fsrsLog: String                      // JSON of FSRS.ReviewLog (Phase 2)
}
