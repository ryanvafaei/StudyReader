import Foundation
import GRDB
import Testing
@testable import StudyReader

/// Themed completion for any reason the queue runs out (T122a, ADR-0022): rated, deleted or suspended. Leaving
/// early never completes. Completion happens once per session. Uses a fixed clock and the app's own review service
/// (fuzz on), so the assertions are on states, summaries and the completion instant, not on card order.
@MainActor
@Suite("Themed completion")
struct ThemedCompletionTests {
    /// 05:00 on the reference day, after the 04:00 review-day boundary.
    private var sessionTime: Date {
        ReviewTestFixture.base.addingTimeInterval(5 * 3_600)
    }

    /// How a card leaves the queue without a rating.
    enum Removal: CaseIterable, Sendable {
        /// The highlight is deleted, which cascades to its card; `reloadCurrent()` drops it.
        case deleted
        /// Frequency Off on the current card; `setFrequency(.off)` drops it.
        case suspended
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

    /// A highlight in `documentId` with its passive card, new and due at the review-day base. Returns the highlight id.
    @discardableResult
    private func insertCard(_ env: AppEnvironment, documentId: String, text: String) async throws -> String {
        let highlight = TestData.highlight(documentId: documentId, text: text)
        try await env.highlightRepository.insert(highlight)
        let card = try ReviewCardFactory.passive(highlightId: highlight.id, now: ReviewTestFixture.base)
        try await env.reviewCardRepository.insertPassiveCards([card])
        return highlight.id
    }

    private func createReview(_ env: AppEnvironment, documentId: String) async throws -> ThemedReview {
        var filter = ThemedReviewFilter()
        filter.documentIds = [documentId]
        let draft = ThemedReviewDraft(
            name: "Exam week",
            filter: filter,
            cardsPerSession: 5,
            interval: .daily,
            orderMode: .dueFirst
        )
        return try await env.themedReviewRepository.create(draft, at: ReviewTestFixture.base)
    }

    private func completedAt(_ env: AppEnvironment, _ review: ThemedReview) async throws -> Date? {
        try #require(try await env.themedReviewRepository.fetch(id: review.id)).lastCompletedAt
    }

    /// Creates a session over `count` new cards in one themed review and starts it.
    private func startedModel(
        count: Int,
        clock: FixedNow
    ) async throws -> (session: AppSession, review: ThemedReview, model: ReviewSessionModel) {
        let session = try makeSession(clock: clock)
        let env = session.environment
        let documentId = try await insertDocument(env)
        for index in 0..<count {
            try await insertCard(env, documentId: documentId, text: "Card \(index)")
        }
        let review = try await createReview(env, documentId: documentId)
        let model = ReviewSessionModel(session: session, context: .themed(id: review.id))
        await model.loadPlan()
        await model.start()
        return (session, review, model)
    }

    /// Removes the current card the way `how` says, then returns (the caller checks the model state).
    private func removeCurrent(_ model: ReviewSessionModel, env: AppEnvironment, how: Removal) async throws {
        let item = try #require(model.queue.first)
        switch how {
        case .deleted:
            _ = try await env.highlightRepository.delete(id: item.highlight.id, fileStore: env.fileStore)
            await model.reloadCurrent()
        case .suspended:
            await model.setFrequency(.off)
        }
    }

    @Test func rateSomeThenLastIsDeletedCompletes() async throws {
        let clock = FixedNow(sessionTime)
        let (session, review, model) = try await startedModel(count: 3, clock: clock)
        let env = session.environment
        defer { TestFileStore.remove(env.fileStore) }

        await model.rate(.good)
        await model.rate(.good)
        #expect(model.phase == .reviewing)
        #expect(model.queue.count == 1)
        #expect(try await completedAt(env, review) == nil)

        let last = try #require(model.queue.first)
        _ = try await env.highlightRepository.delete(id: last.highlight.id, fileStore: env.fileStore)
        await model.reloadCurrent()

        guard case .finished(let summary) = model.phase else {
            Issue.record("The themed session should finish when its last card is deleted.")
            return
        }
        #expect(summary.reviewed == 2)
        #expect(model.errorMessage == nil)
        let completed = try #require(try await completedAt(env, review))
        #expect(abs(completed.timeIntervalSince(sessionTime)) < 1)

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func rateSomeThenLastIsSuspendedCompletes() async throws {
        let clock = FixedNow(sessionTime)
        let (session, review, model) = try await startedModel(count: 2, clock: clock)
        let env = session.environment
        defer { TestFileStore.remove(env.fileStore) }

        await model.rate(.good)
        #expect(model.phase == .reviewing)
        #expect(try await completedAt(env, review) == nil)

        await model.setFrequency(.off)

        guard case .finished(let summary) = model.phase else {
            Issue.record("The themed session should finish when its last card is suspended.")
            return
        }
        #expect(summary.reviewed == 1)
        #expect(model.errorMessage == nil)
        let completed = try #require(try await completedAt(env, review))
        #expect(abs(completed.timeIntervalSince(sessionTime)) < 1)

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(arguments: Removal.allCases)
    func allCardsDroppedWithoutRatingCompletes(how: Removal) async throws {
        let clock = FixedNow(sessionTime)
        let (session, review, model) = try await startedModel(count: 2, clock: clock)
        let env = session.environment
        defer { TestFileStore.remove(env.fileStore) }

        try await removeCurrent(model, env: env, how: how)
        #expect(model.phase == .reviewing)
        #expect(try await completedAt(env, review) == nil)
        try await removeCurrent(model, env: env, how: how)

        guard case .finished(let summary) = model.phase else {
            Issue.record("The themed session should finish when every card is dropped.")
            return
        }
        #expect(summary.reviewed == 0)
        #expect(summary.remembered == 0)
        #expect(model.errorMessage == nil)
        let completed = try #require(try await completedAt(env, review))
        #expect(abs(completed.timeIntervalSince(sessionTime)) < 1)

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func cardDeletedAfterPlanningBeforeStartCompletes() async throws {
        let clock = FixedNow(sessionTime)
        let session = try makeSession(clock: clock)
        let env = session.environment
        defer { TestFileStore.remove(env.fileStore) }

        let documentId = try await insertDocument(env)
        let highlightId = try await insertCard(env, documentId: documentId, text: "Card 0")
        let review = try await createReview(env, documentId: documentId)

        let model = ReviewSessionModel(session: session, context: .themed(id: review.id))
        await model.loadPlan()
        // The plan lists the card, but it is gone when the session reads it.
        _ = try await env.highlightRepository.delete(id: highlightId, fileStore: env.fileStore)
        await model.start()

        guard case .finished(let summary) = model.phase else {
            Issue.record("A session whose cards are all gone at start should finish at once.")
            return
        }
        #expect(summary.reviewed == 0)
        #expect(model.errorMessage == nil)
        #expect(try await completedAt(env, review) != nil)

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func completionHappensOnceAndLaterActionsDoNotRewriteIt() async throws {
        let clock = FixedNow(sessionTime)
        let (session, review, model) = try await startedModel(count: 2, clock: clock)
        let env = session.environment
        defer { TestFileStore.remove(env.fileStore) }

        await model.rate(.good)
        await model.rate(.good)
        let firstCompletion = try #require(try await completedAt(env, review))
        #expect(abs(firstCompletion.timeIntervalSince(sessionTime)) < 1)

        // Later actions on the finished session must not complete it again at a later instant.
        clock.set(sessionTime.addingTimeInterval(3_600))
        await model.rate(.good)
        await model.reloadCurrent()
        await model.setFrequency(.off)

        guard case .finished(let summary) = model.phase else {
            Issue.record("The session should stay finished.")
            return
        }
        #expect(summary.reviewed == 2)
        #expect(try await completedAt(env, review) == firstCompletion)

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func leavingEarlyAfterADropDoesNotComplete() async throws {
        let clock = FixedNow(sessionTime)
        let (session, review, model) = try await startedModel(count: 3, clock: clock)
        let env = session.environment
        defer { TestFileStore.remove(env.fileStore) }

        await model.rate(.good)
        // A drop that leaves a card in the queue must not complete the review.
        try await removeCurrent(model, env: env, how: .deleted)
        #expect(model.phase == .reviewing)
        #expect(model.queue.count == 1)

        model.endSession()

        #expect(model.phase == .idle)
        #expect(try await completedAt(env, review) == nil)

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }
}
