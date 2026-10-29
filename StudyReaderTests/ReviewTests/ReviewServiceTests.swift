import Foundation
import GRDB
import Testing
@testable import StudyReader

/// Shared seeding for the review-service tests: a UTC calendar, the 00:00 base of the reference day and
/// passive cards in a category set to Normal frequency.
enum ReviewTestFixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// 00:00 UTC of the reference day. Test times are offsets from here.
    static var base: Date {
        calendar.startOfDay(for: TestData.referenceDate)
    }

    /// A fixed seed for themed sessions, so their order is repeatable.
    static let makeSeed: @Sendable () -> UInt64 = { 42 }

    static func service(_ env: AppEnvironment, clock: FixedNow) -> ReviewService {
        ReviewService(
            cards: env.reviewCardRepository,
            highlights: env.highlightRepository,
            themedReviews: env.themedReviewRepository,
            now: clock,
            calendar: calendar,
            scheduler: ReviewScheduler(enableFuzz: false),
            makeSeed: makeSeed
        )
    }

    /// Inserts a document, one highlight and its passive card (new, due at `base`). The category is set to
    /// Normal first, so the card is not suspended.
    static func seedCard(
        _ env: AppEnvironment,
        text: String = "Sample highlight text"
    ) async throws -> (highlight: Highlight, card: ReviewCard) {
        try await env.categoryRepository.setFrequency(id: BuiltinCategory.lectureSlides.id, .normal)
        let document = TestData.document()
        try await env.documentRepository.insert(document)
        let highlight = TestData.highlight(documentId: document.id, text: text)
        try await env.highlightRepository.insert(highlight)
        let card = try ReviewCardFactory.passive(highlightId: highlight.id, now: base)
        try await env.reviewCardRepository.insertPassiveCards([card])
        return (highlight, card)
    }
}

@Suite("ReviewService")
struct ReviewServiceTests {
    private let base = ReviewTestFixture.base

    @Test func ratingUpdatesCardAndLogsReview() async throws {
        let time = base.addingTimeInterval(5 * 3_600)
        let clock = FixedNow(time)
        let env = try AppEnvironment.inMemory(now: clock)
        let (_, card) = try await ReviewTestFixture.seedCard(env)
        let service = ReviewTestFixture.service(env, clock: clock)

        let outcome = try await service.rate(cardId: card.id, rating: .good, context: .daily)

        let expected = try ReviewScheduler(enableFuzz: false).schedule(
            StoredFSRSCard.new(due: base),
            rating: .good,
            now: time,
            retention: 0.90
        )
        #expect(outcome.card.state == .review)
        #expect(outcome.card.dueAt == expected.card.due.storageRounded)
        #expect(outcome.card.introducedAt == time)

        #expect(outcome.log.cardId == card.id)
        #expect(outcome.log.rating == ReviewRating.good.rawValue)
        #expect(outcome.log.sessionKind == .daily)
        #expect(outcome.log.themedReviewId == nil)
        #expect(outcome.log.reviewedAt == time)

        let logs = try await env.database.writer.read { db in
            try ReviewLogEntry.fetchAll(db)
        }
        #expect(logs == [outcome.log])

        let storedLog = try StoredFSRSLog(json: outcome.log.fsrsLog)
        #expect(storedLog.state == .new)
        #expect(storedLog.rating == .good)
        #expect(storedLog.review == time)

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func dailyPlanUsesTheDayBoundary() async throws {
        // Rated at 03:00, before the 04:00 boundary, so it belongs to yesterday's review day.
        let clock = FixedNow(base.addingTimeInterval(3 * 3_600))
        let env = try AppEnvironment.inMemory(now: clock)
        let (_, first) = try await ReviewTestFixture.seedCard(env, text: "First")
        let (_, second) = try await ReviewTestFixture.seedCard(env, text: "Second")
        let service = ReviewTestFixture.service(env, clock: clock)
        _ = try await service.rate(cardId: first.id, rating: .good, context: .daily)

        // 05:00 is inside the review day that started at 04:00. Yesterday's rating must not use today's budget.
        clock.set(base.addingTimeInterval(5 * 3_600))
        let limits = DailyLimits(dailyLimit: 1, newPerDay: 5)
        let plan = try await service.dailyPlan(limits: limits)

        #expect(!plan.isEmpty)
        #expect(plan.cardIds == [second.id])
        #expect(plan.dueCount == 0)
        #expect(plan.newCount == 1)

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func rateRejectsSuspendedAndMissing() async throws {
        let clock = FixedNow(base.addingTimeInterval(5 * 3_600))
        let env = try AppEnvironment.inMemory(now: clock)
        let service = ReviewTestFixture.service(env, clock: clock)

        let (_, suspended) = try await ReviewTestFixture.seedCard(env, text: "Suspended")
        try await env.reviewCardRepository.updateFrequencyOverride(cardId: suspended.id, override: .off, rescheduled: nil)
        await #expect(throws: ReviewServiceError.cardSuspended) {
            _ = try await service.rate(cardId: suspended.id, rating: .good, context: .daily)
        }

        let (deleted, removedCard) = try await ReviewTestFixture.seedCard(env, text: "Deleted")
        try await env.highlightRepository.delete(id: deleted.id, fileStore: env.fileStore)
        await #expect(throws: ReviewServiceError.cardMissing) {
            _ = try await service.rate(cardId: removedCard.id, rating: .good, context: .daily)
        }

        // Nothing was written for the rejected ratings.
        let logCount = try await env.database.writer.read { db in
            try ReviewLogEntry.fetchCount(db)
        }
        #expect(logCount == 0)
        let stored = try #require(try await env.reviewCardRepository.fetch(id: suspended.id))
        #expect(stored.state == .new)
        #expect(stored.introducedAt == nil)

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func persistsAcrossANewService() async throws {
        let clock = FixedNow(base.addingTimeInterval(5 * 3_600))
        let env = try AppEnvironment.inMemory(now: clock)
        for text in ["One", "Two", "Three"] {
            _ = try await ReviewTestFixture.seedCard(env, text: text)
        }

        let firstService = ReviewTestFixture.service(env, clock: clock)
        let initial = try await firstService.dailyPlan(limits: .defaults)
        #expect(initial.cardIds.count == 3)

        _ = try await firstService.rate(cardId: initial.cardIds[0], rating: .good, context: .daily)
        _ = try await firstService.rate(cardId: initial.cardIds[1], rating: .good, context: .daily)

        let secondService = ReviewTestFixture.service(env, clock: clock)
        let plan = try await secondService.dailyPlan(limits: .defaults)
        #expect(plan.cardIds == [initial.cardIds[2]])

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }
}
