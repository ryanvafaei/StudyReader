import Foundation
import GRDB
import Testing
@testable import StudyReader

/// Themed sessions (SPEC F-20, ADR-0022): the plan, the logging of ratings, the rated-today exclusion and the
/// completion rule. The session tests use the app's own review service (fuzz on, random seed), so they assert
/// states and ids, not exact dates. The planning and logging tests use a fixed seed and no fuzz.
@MainActor
@Suite("Themed sessions")
struct ThemedSessionTests {
    /// 05:00 on the reference day, after the 04:00 review-day boundary.
    private var sessionTime: Date {
        ReviewTestFixture.base.addingTimeInterval(5 * 3_600)
    }

    private func makeSession(clock: FixedNow) throws -> AppSession {
        let inMemory = try AppEnvironment.inMemory(now: clock)
        let environment = AppEnvironment(
            fileStore: inMemory.fileStore,
            database: inMemory.database,
            now: clock,
            settingsStore: TestSettings.make(),
            sleeper: ImmediateSleeper()
        )
        let session = AppSession(environment: environment)
        session.settings.showFourRatingButtons = false
        return session
    }

    /// A document with Normal frequency, so its cards are not suspended.
    private func insertDocument(_ env: AppEnvironment) async throws -> String {
        try await env.categoryRepository.setFrequency(id: BuiltinCategory.lectureSlides.id, .normal)
        let document = TestData.document()
        try await env.documentRepository.insert(document)
        return document.id
    }

    /// A highlight in `documentId` with its passive card (new, due at `due`, by default the review-day base).
    private func insertCard(
        _ env: AppEnvironment,
        documentId: String,
        text: String,
        due: Date = ReviewTestFixture.base
    ) async throws -> ReviewCard {
        let highlight = TestData.highlight(documentId: documentId, text: text)
        try await env.highlightRepository.insert(highlight)
        let card = try ReviewCardFactory.passive(highlightId: highlight.id, now: due)
        try await env.reviewCardRepository.insertPassiveCards([card])
        return card
    }

    private func createReview(
        _ env: AppEnvironment,
        documentIds: [String],
        cardsPerSession: Int = 5,
        orderMode: ReviewOrderMode = .dueFirst
    ) async throws -> ThemedReview {
        var filter = ThemedReviewFilter()
        filter.documentIds = documentIds
        let draft = ThemedReviewDraft(
            name: "Exam week",
            filter: filter,
            cardsPerSession: cardsPerSession,
            interval: .daily,
            orderMode: orderMode
        )
        return try await env.themedReviewRepository.create(draft, at: ReviewTestFixture.base)
    }

    private func completedAt(_ env: AppEnvironment, _ review: ThemedReview) async throws -> Date? {
        try #require(try await env.themedReviewRepository.fetch(id: review.id)).lastCompletedAt
    }

    private func storedCard(_ env: AppEnvironment, _ id: String) async throws -> ReviewCard {
        try #require(try await env.reviewCardRepository.fetch(id: id))
    }

    @Test("the plan holds only the filter's cards, capped at cardsPerSession", arguments: ReviewOrderMode.allCases)
    func planFollowsFilterAndVolume(order: ReviewOrderMode) async throws {
        let clock = FixedNow(sessionTime)
        let session = try makeSession(clock: clock)
        let env = session.environment
        defer { TestFileStore.remove(env.fileStore) }

        let inside = try await insertDocument(env)
        let outside = try await insertDocument(env)
        let base = ReviewTestFixture.base

        // Four cards due by the session time, inserted out of due order, then three due on later days.
        var dueCards: [(id: String, at: Date)] = []
        let dueOffsets: [TimeInterval] = [300, 60, 180, 0]
        for (index, offset) in dueOffsets.enumerated() {
            let at = base.addingTimeInterval(offset)
            let card = try await insertCard(env, documentId: inside, text: "Due \(index)", due: at)
            dueCards.append((card.id, at))
        }
        var laterCards: [(id: String, at: Date)] = []
        let laterOffsets: [TimeInterval] = [3 * 86_400, 2 * 86_400 + 3_600, 2 * 86_400]
        for (index, offset) in laterOffsets.enumerated() {
            let at = base.addingTimeInterval(offset)
            let card = try await insertCard(env, documentId: inside, text: "Later \(index)", due: at)
            laterCards.append((card.id, at))
        }
        _ = try await insertCard(env, documentId: outside, text: "Outside", due: base.addingTimeInterval(-3_600))

        let insideIds = Set((dueCards + laterCards).map(\.id))
        let dueSorted = dueCards.sorted { $0.at < $1.at }.map(\.id)
        let laterSorted = laterCards.sorted { $0.at < $1.at }.map(\.id)

        let review = try await createReview(env, documentIds: [inside], cardsPerSession: 5, orderMode: order)
        let service = ReviewTestFixture.service(env, clock: clock)
        let plan = try await service.themedPlan(reviewId: review.id)

        #expect(plan.review.id == review.id)
        #expect(plan.cardIds.count == 5)
        #expect(Set(plan.cardIds).count == 5)
        #expect(Set(plan.cardIds).isSubset(of: insideIds))
        if order == .dueFirst {
            // Due cards by due date, then the earliest later card.
            #expect(plan.cardIds == Array((dueSorted + laterSorted).prefix(5)))
        }

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func ratingsAreLoggedAsThemed() async throws {
        let clock = FixedNow(sessionTime)
        let session = try makeSession(clock: clock)
        let env = session.environment
        defer { TestFileStore.remove(env.fileStore) }

        let documentId = try await insertDocument(env)
        let first = try await insertCard(env, documentId: documentId, text: "Card 0")
        let second = try await insertCard(env, documentId: documentId, text: "Card 1")
        let review = try await createReview(env, documentIds: [documentId])

        let firstBefore = try await storedCard(env, first.id)
        let secondBefore = try await storedCard(env, second.id)
        #expect(firstBefore.state == .new)
        #expect(secondBefore.state == .new)

        let model = ReviewSessionModel(session: session, context: .themed(id: review.id))
        await model.loadPlan()
        await model.start()
        #expect(model.themedReviewName == review.name)
        await model.rate(.good)
        await model.rate(.again)

        let logs = try await env.database.writer.read { db in
            try ReviewLogEntry.fetchAll(db)
        }
        #expect(logs.count == 2)
        #expect(logs.allSatisfy { $0.sessionKind == .themed })
        #expect(logs.allSatisfy { $0.themedReviewId == review.id })
        #expect(Set(logs.map(\.cardId)) == Set([first.id, second.id]))

        // Each card was rated once, so each card's FSRS state moved on from new.
        for (id, before) in [(first.id, firstBefore), (second.id, secondBefore)] {
            let after = try await storedCard(env, id)
            #expect(after.state != .new)
            #expect(after.fsrsCard != before.fsrsCard)
        }

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func themedRatedCardsLeaveTodaysDailyReview() async throws {
        let clock = FixedNow(sessionTime)
        let session = try makeSession(clock: clock)
        let env = session.environment
        defer { TestFileStore.remove(env.fileStore) }

        let documentId = try await insertDocument(env)
        let card = try await insertCard(env, documentId: documentId, text: "Rated in the themed review")
        let review = try await createReview(env, documentIds: [documentId])
        let service = ReviewTestFixture.service(env, clock: clock)

        let beforeDaily = try await service.dailyPlan(limits: .defaults)
        #expect(beforeDaily.cardIds.contains(card.id))
        let beforeThemed = try await service.themedPlan(reviewId: review.id)
        #expect(beforeThemed.cardIds.contains(card.id))

        let outcome = try await service.rate(cardId: card.id, rating: .good, context: .themed(id: review.id))

        let afterDaily = try await service.dailyPlan(limits: .defaults)
        #expect(!afterDaily.cardIds.contains(card.id))
        // Rated today in any session, so the themed plan leaves it out too (ADR-0022).
        let afterThemed = try await service.themedPlan(reviewId: review.id)
        #expect(!afterThemed.cardIds.contains(card.id))

        // SPEC F-20: the card is back once it is due on a later review day.
        let backDay = ReviewDay.start(after: outcome.card.dueAt, calendar: ReviewTestFixture.calendar)
        #expect(backDay > outcome.card.dueAt)
        clock.set(backDay)
        let laterDaily = try await service.dailyPlan(limits: .defaults)
        #expect(laterDaily.cardIds.contains(card.id))

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func finishingMarksCompleted() async throws {
        let clock = FixedNow(sessionTime)
        let session = try makeSession(clock: clock)
        let env = session.environment
        defer { TestFileStore.remove(env.fileStore) }

        let documentId = try await insertDocument(env)
        for index in 0..<2 {
            _ = try await insertCard(env, documentId: documentId, text: "Card \(index)")
        }
        let review = try await createReview(env, documentIds: [documentId])
        #expect(try await completedAt(env, review) == nil)

        let model = ReviewSessionModel(session: session, context: .themed(id: review.id))
        await model.loadPlan()
        await model.start()
        await model.rate(.good)
        #expect(model.phase == .reviewing)
        await model.rate(.good)

        guard case .finished(let summary) = model.phase else {
            Issue.record("The themed session should finish when its queue empties through ratings.")
            return
        }
        #expect(summary.reviewed == 2)
        #expect(model.errorMessage == nil)
        let completed = try #require(try await completedAt(env, review))
        #expect(abs(completed.timeIntervalSince(sessionTime)) < 1)

        // ThemedReviewSchedule (daily): done for the rest of the review day, due again at the next 04:00.
        let calendar = ReviewTestFixture.calendar
        let fetched = try #require(try await env.themedReviewRepository.fetch(id: review.id))
        let nextBoundary = ReviewDay.start(after: sessionTime, calendar: calendar)
        #expect(!ThemedReviewSchedule.isDue(fetched, now: sessionTime, calendar: calendar))
        #expect(!ThemedReviewSchedule.isDue(fetched, now: ReviewTestFixture.base.addingTimeInterval(23 * 3_600), calendar: calendar))
        #expect(!ThemedReviewSchedule.isDue(fetched, now: nextBoundary.addingTimeInterval(-1), calendar: calendar))
        #expect(ThemedReviewSchedule.isDue(fetched, now: nextBoundary, calendar: calendar))

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func leavingEarlyDoesNotComplete() async throws {
        let clock = FixedNow(sessionTime)
        let session = try makeSession(clock: clock)
        let env = session.environment
        defer { TestFileStore.remove(env.fileStore) }

        let documentId = try await insertDocument(env)
        for index in 0..<2 {
            _ = try await insertCard(env, documentId: documentId, text: "Card \(index)")
        }
        let review = try await createReview(env, documentIds: [documentId])

        let model = ReviewSessionModel(session: session, context: .themed(id: review.id))
        await model.loadPlan()
        await model.start()
        await model.rate(.good)
        model.endSession()

        #expect(model.phase == .idle)
        #expect(model.themedReviewName == nil)
        #expect(try await completedAt(env, review) == nil)

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func emptySelectionCompletesAtOnce() async throws {
        let clock = FixedNow(sessionTime)
        let session = try makeSession(clock: clock)
        let env = session.environment
        defer { TestFileStore.remove(env.fileStore) }

        // A filter that matches no document, so the selection is empty.
        let review = try await createReview(env, documentIds: [UUID().uuidString])
        #expect(try await completedAt(env, review) == nil)

        let model = ReviewSessionModel(session: session, context: .themed(id: review.id))
        await model.loadPlan()

        guard case .finished(let summary) = model.phase else {
            Issue.record("An empty themed selection should finish at once.")
            return
        }
        #expect(summary.reviewed == 0)
        #expect(model.errorMessage == nil)
        let completed = try #require(try await completedAt(env, review))
        #expect(abs(completed.timeIntervalSince(sessionTime)) < 1)

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }
}
