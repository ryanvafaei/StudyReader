import Foundation

/// SplitMix64 (Vigna). Deterministic for a seed. The service passes a fresh random seed (T122), tests a fixed one.
struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Picks the cards of a themed session from the repository snapshot (SPEC F-20, ADR-0022, ARCHITECTURE §10.2).
/// Pure: the clock and the seed are parameters; no database, no calendar state beyond the caller's `now`.
enum ThemedReviewBuilder {
    /// 1. Drops cards rated today in any session.
    /// 2. Orders them: dueFirst (due cards by dueAt then cardId, then the rest by last review with
    ///    never-reviewed first, then dueAt, then cardId); random (seeded shuffle of the cardId-sorted list).
    /// 3. Keeps `review.cardsPerSession` cards.
    static func build(_ snapshot: ThemedQueueSnapshot, review: ThemedReview, now: Date, seed: UInt64) -> [String] {
        let candidates = snapshot.candidates.filter { !snapshot.ratedTodayCardIds.contains($0.cardId) }

        let ordered: [ReviewQueueEntry]
        switch review.orderMode {
        case .dueFirst:
            ordered = dueFirst(candidates, now: now)
        case .random:
            let sorted = candidates.sorted { $0.cardId < $1.cardId }
            var rng = SeededRandom(seed: seed)
            ordered = sorted.shuffled(using: &rng)
        }

        return ordered.prefix(max(0, review.cardsPerSession)).map(\.cardId)
    }

    private static func dueFirst(_ candidates: [ReviewQueueEntry], now: Date) -> [ReviewQueueEntry] {
        let due = candidates
            .filter { $0.dueAt <= now }
            .sorted { lhs, rhs in
                if lhs.dueAt != rhs.dueAt { return lhs.dueAt < rhs.dueAt }
                return lhs.cardId < rhs.cardId
            }

        let rest = candidates
            .filter { $0.dueAt > now }
            .sorted { lhs, rhs in
                if lhs.lastReviewedAt != rhs.lastReviewedAt {
                    // nil (never reviewed) sorts before any date.
                    guard let lhsLast = lhs.lastReviewedAt else { return true }
                    guard let rhsLast = rhs.lastReviewedAt else { return false }
                    return lhsLast < rhsLast
                }
                if lhs.dueAt != rhs.dueAt { return lhs.dueAt < rhs.dueAt }
                return lhs.cardId < rhs.cardId
            }

        return due + rest
    }
}

/// Whether a themed review is due by its interval (SPEC F-20 AC2, ADR-0022). Review days start at 04:00.
enum ThemedReviewSchedule {
    static func isDue(_ review: ThemedReview, now: Date, calendar: Calendar) -> Bool {
        let interval = review.interval

        guard let lastCompletedAt = review.lastCompletedAt else {
            switch interval.kind {
            case .daily, .everyNDays:
                return true
            case .weekdays:
                return isListedWeekday(interval, now: now, calendar: calendar)
            }
        }

        let todayStart = ReviewDay.start(containing: now, calendar: calendar)
        switch interval.kind {
        case .daily:
            return lastCompletedAt < todayStart
        case .everyNDays:
            let n = max(interval.n ?? 1, 1)
            return ReviewDay.daysBetween(lastCompletedAt, now, calendar: calendar) >= n
        case .weekdays:
            return isListedWeekday(interval, now: now, calendar: calendar) && lastCompletedAt < todayStart
        }
    }

    private static func isListedWeekday(_ interval: ReviewInterval, now: Date, calendar: Calendar) -> Bool {
        (interval.weekdays ?? []).contains(ReviewDay.weekday(of: now, calendar: calendar))
    }
}
