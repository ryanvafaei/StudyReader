import Testing
import Foundation
import FSRS
@testable import StudyReader

/// FSRS-6 scheduler wrapper (T97, ADR-0006, ADR-0021). Fuzz is off and the clock is fixed, so every value is deterministic.
@Suite struct ReviewSchedulerTests {
    private let scheduler = ReviewScheduler(enableFuzz: false)
    private let t = TestData.referenceDate
    private let day: TimeInterval = 86_400

    /// One review at `now`, retention 0.9 unless given.
    private func review(_ card: StoredFSRSCard, _ rating: ReviewRating, at now: Date, retention: Double = 0.9) throws -> ScheduledReview {
        try scheduler.schedule(card, rating: rating, now: now, retention: retention)
    }

    @Test func usesFSRS6Weights() {
        #expect(scheduler.weights.count == ReviewScheduler.fsrs6WeightCount)
        #expect(scheduler.weights == FSRSDefaults.defaultWv6)
        #expect(ReviewScheduler().enableFuzz)
    }

    @Test func newCardMatchesLibraryEmptyCard() {
        let stored = StoredFSRSCard.new(due: t)
        let mapped = ReviewScheduler.libraryCard(from: stored)
        let empty = Card(due: t)
        #expect(mapped.due == empty.due)
        #expect(mapped.stability == empty.stability)
        #expect(mapped.difficulty == empty.difficulty)
        #expect(mapped.elapsedDays == empty.elapsedDays)
        #expect(mapped.scheduledDays == empty.scheduledDays)
        #expect(mapped.learningSteps == empty.learningSteps)
        #expect(mapped.reps == empty.reps)
        #expect(mapped.lapses == empty.lapses)
        #expect(mapped.state == empty.state)
        #expect(mapped.lastReview == empty.lastReview)
        #expect(mapped == empty)
        #expect(ReviewScheduler.storedCard(from: mapped) == stored)
    }

    @Test func stateAndRatingMappingsRoundTrip() {
        for state in ReviewCardState.allCases {
            #expect(ReviewScheduler.storedState(ReviewScheduler.libraryState(state)) == state)
        }
        for rating in ReviewRating.allCases {
            #expect(ReviewScheduler.libraryRating(rating).rawValue == rating.rawValue)
            #expect(ReviewScheduler.storedRating(ReviewScheduler.libraryRating(rating)) == rating)
        }
        #expect(ReviewScheduler.storedRating(.manual) == nil)
    }

    /// Characterization table: scheduledDays after the first review at retention 0.9 (FSRS-6 default weights,
    /// long-term scheduler). Guards library upgrades.
    @Test(arguments: [
        (ReviewRating.again, 1.0),
        (ReviewRating.hard, 2.0),
        (ReviewRating.good, 2.0),
        (ReviewRating.easy, 8.0),
    ])
    func firstReviewTable(rating: ReviewRating, expectedDays: Double) throws {
        let result = try review(.new(due: t), rating, at: t)
        #expect(result.card.state != .new)
        #expect(result.card.reps == 1)
        #expect(result.card.lastReview == t)
        #expect(result.card.due > t)
        #expect(result.card.due == result.card.due.storageRounded)
        #expect(result.log.rating == rating)
        #expect(result.log.state == .new)
        #expect(result.log.review == t)
        #expect(result.card.scheduledDays == expectedDays)
        #expect(result.card.due == t.addingTimeInterval(expectedDays * day))
    }

    @Test func firstReviewDuesAreOrderedByRating() throws {
        let dues = try ReviewRating.allCases.map { try review(.new(due: t), $0, at: t).card.due }
        #expect(dues[0] <= dues[1])
        #expect(dues[1] <= dues[2])
        #expect(dues[2] <= dues[3])
    }

    @Test func repeatedForgetting() throws {
        var card = StoredFSRSCard.new(due: t)
        var now = t
        for _ in 0..<2 {
            card = try review(card, .good, at: now).card
            now = card.due
        }
        #expect(card.lapses == 0)
        var previousInterval = card.scheduledDays
        for expectedLapses in 1...3 {
            let result = try review(card, .again, at: now)
            #expect(result.card.lapses == expectedLapses)
            #expect(result.card.scheduledDays <= previousInterval)
            #expect(result.card.scheduledDays >= 1)
            previousInterval = result.card.scheduledDays
            card = result.card
            now = card.due
        }
    }

    @Test func longIntervals() throws {
        var card = StoredFSRSCard.new(due: t)
        var now = t
        var previousInterval = 0.0
        let limit = t.addingTimeInterval(36_500 * day)
        for _ in 0..<6 {
            let result = try review(card, .good, at: now)
            #expect(result.card.scheduledDays >= previousInterval)
            #expect(result.card.due <= limit)
            previousInterval = result.card.scheduledDays
            card = result.card
            now = card.due
        }
        #expect(previousInterval > 30)
    }

    /// Same review-state card, rating good, three retention levels.
    @Test func retentionPerFrequency() throws {
        let card = StoredFSRSCard(
            due: t,
            stability: 10,
            difficulty: 5,
            elapsedDays: 10,
            scheduledDays: 10,
            reps: 3,
            state: .review,
            lastReview: t.addingTimeInterval(-10 * day)
        )
        let table: [(label: String, retention: Double)] = [("low", 0.80), ("normal", 0.90), ("high", 0.95)]
        let intervals = try table.map { try review(card, .good, at: t, retention: $0.retention).card.scheduledDays }
        #expect(intervals[0] >= intervals[1])
        #expect(intervals[1] >= intervals[2])
        #expect(intervals[0] > intervals[2])
    }

    @Test func fuzzOffIsDeterministic() throws {
        let first = try review(.new(due: t), .good, at: t)
        let second = try review(.new(due: t), .good, at: t)
        #expect(first == second)
    }

    @Test func logDescribesTheCardBeforeTheReview() throws {
        let first = try review(.new(due: t), .good, at: t).card
        let second = try review(first, .good, at: first.due)
        #expect(second.log.state == first.state)
        #expect(second.log.stability == first.stability)
        #expect(second.log.difficulty == first.difficulty)
        #expect(second.log.review == first.due)
        #expect(second.card.reps == 2)
    }

    @Test(arguments: [0.0, 1.0, 1.2, -0.5, Double.nan])
    func rejectsInvalidRetention(retention: Double) {
        #expect(throws: ReviewSchedulerError.invalidRetention) {
            try scheduler.schedule(.new(due: t), rating: .good, now: t, retention: retention)
        }
    }

    @Test func rescheduledDueFollowsRetention() {
        let lastReview = t
        let card = StoredFSRSCard(
            due: t.addingTimeInterval(5 * day),
            stability: 10,
            difficulty: 5,
            scheduledDays: 5,
            reps: 2,
            state: .review,
            lastReview: lastReview
        )
        let normal = scheduler.rescheduledDue(card, retention: 0.9)
        let high = scheduler.rescheduledDue(card, retention: 0.95)
        let low = scheduler.rescheduledDue(card, retention: 0.80)
        #expect(normal == lastReview.addingTimeInterval(10 * day))
        #expect(high < normal)
        #expect(low > normal)
        #expect(high >= lastReview.addingTimeInterval(day))
        #expect(low <= lastReview.addingTimeInterval(36_500 * day))
    }

    @Test func rescheduledDueKeepsDueWhenNotApplicable() {
        let newCard = StoredFSRSCard.new(due: t)
        #expect(scheduler.rescheduledDue(newCard, retention: 0.9) == newCard.due)

        let noLastReview = StoredFSRSCard(due: t, stability: 10, state: .review, lastReview: nil)
        #expect(scheduler.rescheduledDue(noLastReview, retention: 0.9) == t)

        let reviewed = StoredFSRSCard(due: t, stability: 10, state: .review, lastReview: t.addingTimeInterval(-day))
        #expect(scheduler.rescheduledDue(reviewed, retention: 0) == t)
        #expect(scheduler.rescheduledDue(reviewed, retention: 1) == t)
    }

    @Test func rescheduledDueClampsToOneDayAndMaximum() {
        let tiny = StoredFSRSCard(due: t, stability: 0.001, state: .review, lastReview: t)
        #expect(scheduler.rescheduledDue(tiny, retention: 0.9) == t.addingTimeInterval(day))
        let huge = StoredFSRSCard(due: t, stability: 1_000_000, state: .review, lastReview: t)
        #expect(scheduler.rescheduledDue(huge, retention: 0.9) == t.addingTimeInterval(36_500 * day))
    }
}
