import Foundation
import FSRS

/// Result of one review: the card after it and the log describing the card before it (ADR-0021).
struct ScheduledReview: Sendable, Equatable {
    var card: StoredFSRSCard      // after the review; due and lastReview storage-rounded
    var log: StoredFSRSLog        // review = now.storageRounded
}

enum ReviewSchedulerError: Error, Equatable {
    case invalidRetention          // retention not in the open interval (0, 1)
}

/// The only app file that imports swift-fsrs (ADR-0006, ADR-0021). Pure: time and fuzz are injected
/// by the caller (`now`, `enableFuzz`); no database, no `Date()`.
///
/// Library API used (swift-fsrs main @ 4fbaf20, FSRS-6 is public there): `FSRSDefaults.defaultWv6`,
/// `FSRSParameters(requestRetention:w:enableFuzz:enableShortTerm:)`, `FSRS(parameters:)`,
/// `FSRS.next(card:now:grade:)` returning `RecordLogItem`, `Card`, `ReviewLog`, `Rating`, `CardState`.
struct ReviewScheduler: Sendable {
    static let fsrs6WeightCount = 21

    /// The library's default FSRS-6 weights (never hard-coded here).
    var weights: [Double]
    var enableFuzz: Bool

    init(enableFuzz: Bool = true) {
        self.weights = FSRSDefaults.defaultWv6
        self.enableFuzz = enableFuzz
    }

    /// FSRS(parameters: requestRetention: retention, w: weights, enableFuzz, enableShortTerm: false), next(card:now:grade:).
    func schedule(_ card: StoredFSRSCard, rating: ReviewRating, now: Date, retention: Double) throws -> ScheduledReview {
        guard Self.isValid(retention: retention) else { throw ReviewSchedulerError.invalidRetention }

        let reviewTime = now.storageRounded
        let parameters = FSRSParameters(
            requestRetention: retention,
            w: weights,
            enableFuzz: enableFuzz,
            enableShortTerm: false
        )
        let fsrs = FSRS(parameters: parameters)
        let result = try fsrs.next(card: Self.libraryCard(from: card), now: reviewTime, grade: Self.libraryRating(rating))
        return ScheduledReview(
            card: Self.storedCard(from: result.card),
            log: Self.storedLog(from: result.log, previous: card)
        )
    }

    /// ADR-0021 formula. state == .new or lastReview == nil → card.due unchanged. Otherwise
    /// lastReview + days, days = clamp(round(S / F * (pow(retention, 1 / D) - 1)), 1...36_500), D = -weights[20],
    /// F = pow(0.9, 1 / D) - 1, S = card.stability; one day = 86_400 s (as in FSRS); result storage-rounded. No fuzz.
    /// Invalid retention → card.due.
    func rescheduledDue(_ card: StoredFSRSCard, retention: Double) -> Date {
        guard Self.isValid(retention: retention),
              card.state != .new,
              let lastReview = card.lastReview,
              weights.count == Self.fsrs6WeightCount else { return card.due }

        let decay = -weights[Self.fsrs6WeightCount - 1]
        let factor = pow(0.9, 1 / decay) - 1
        let rawDays = (card.stability / factor * (pow(retention, 1 / decay) - 1)).rounded()
        guard rawDays.isFinite else { return card.due }
        let days = min(max(rawDays, 1), 36_500)
        return lastReview.addingTimeInterval(days * 86_400).storageRounded
    }

    // MARK: - Mapping (internal so tests can call them)

    static func isValid(retention: Double) -> Bool {
        retention > 0 && retention < 1
    }

    static func libraryState(_ state: ReviewCardState) -> CardState {
        switch state {
        case .new: return .new
        case .learning: return .learning
        case .review: return .review
        case .relearning: return .relearning
        }
    }

    static func storedState(_ state: CardState) -> ReviewCardState {
        switch state {
        case .new: return .new
        case .learning: return .learning
        case .review: return .review
        case .relearning: return .relearning
        }
    }

    static func libraryRating(_ rating: ReviewRating) -> Rating {
        switch rating {
        case .again: return .again
        case .hard: return .hard
        case .good: return .good
        case .easy: return .easy
        }
    }

    /// `.manual` has no counterpart in our enum; it is never produced by `next(card:now:grade:)`.
    static func storedRating(_ rating: Rating) -> ReviewRating? {
        switch rating {
        case .manual: return nil
        case .again: return .again
        case .hard: return .hard
        case .good: return .good
        case .easy: return .easy
        }
    }

    static func libraryCard(from card: StoredFSRSCard) -> Card {
        Card(
            due: card.due,
            stability: card.stability,
            difficulty: card.difficulty,
            elapsedDays: card.elapsedDays,
            scheduledDays: card.scheduledDays,
            learningSteps: card.learningSteps,
            reps: card.reps,
            lapses: card.lapses,
            state: libraryState(card.state),
            lastReview: card.lastReview
        )
    }

    static func storedCard(from card: Card) -> StoredFSRSCard {
        StoredFSRSCard(
            due: card.due.storageRounded,
            stability: card.stability,
            difficulty: card.difficulty,
            elapsedDays: card.elapsedDays,
            scheduledDays: card.scheduledDays,
            learningSteps: card.learningSteps,
            reps: card.reps,
            lapses: card.lapses,
            state: storedState(card.state),
            lastReview: card.lastReview?.storageRounded
        )
    }

    /// The library's log fields `state`, `due`, `stability` and `difficulty` are optional; a missing value
    /// falls back to the card as it was before the review.
    static func storedLog(from log: ReviewLog, previous: StoredFSRSCard) -> StoredFSRSLog {
        StoredFSRSLog(
            rating: storedRating(log.rating) ?? .again,
            state: log.state.map(storedState) ?? previous.state,
            due: (log.due ?? previous.due).storageRounded,
            stability: log.stability ?? previous.stability,
            difficulty: log.difficulty ?? previous.difficulty,
            elapsedDays: log.elapsedDays,
            lastElapsedDays: log.lastElapsedDays,
            scheduledDays: log.scheduledDays,
            learningSteps: log.learningSteps,
            review: log.review.storageRounded
        )
    }
}
