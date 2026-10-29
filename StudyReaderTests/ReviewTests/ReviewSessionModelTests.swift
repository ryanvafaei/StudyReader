import Foundation
import GRDB
import Testing
@testable import StudyReader

/// One row of the key table: the key pressed, the button layout, and the action it must give (ADR-0022).
struct ReviewKeyCase: Sendable, CustomTestStringConvertible {
    var fourButtons: Bool
    var key: Character
    var expected: ReviewKeyAction?

    var testDescription: String {
        let keyName = key == " " ? "space" : String(key)
        return "\(fourButtons ? "four" : "two") buttons, key \(keyName)"
    }
}

private let reviewKeyCases: [ReviewKeyCase] = [
    ReviewKeyCase(fourButtons: false, key: "1", expected: .rate(.again)),
    ReviewKeyCase(fourButtons: false, key: "2", expected: .rate(.good)),
    ReviewKeyCase(fourButtons: false, key: "3", expected: nil),
    ReviewKeyCase(fourButtons: false, key: "4", expected: nil),
    ReviewKeyCase(fourButtons: false, key: "x", expected: nil),
    ReviewKeyCase(fourButtons: false, key: " ", expected: nil),
    ReviewKeyCase(fourButtons: true, key: "1", expected: .rate(.again)),
    ReviewKeyCase(fourButtons: true, key: "2", expected: .rate(.hard)),
    ReviewKeyCase(fourButtons: true, key: "3", expected: .rate(.good)),
    ReviewKeyCase(fourButtons: true, key: "4", expected: .rate(.easy)),
    ReviewKeyCase(fourButtons: true, key: "5", expected: nil),
    ReviewKeyCase(fourButtons: true, key: " ", expected: nil),
]

private let secondsPerDay: TimeInterval = 86_400
private let secondsPerHour: TimeInterval = 3_600

@MainActor
@Suite("ReviewSessionModel")
struct ReviewSessionModelTests {
    /// The session clock: 05:00 on the reference day, after the 04:00 review-day boundary.
    private var sessionTime: Date {
        ReviewTestFixture.base.addingTimeInterval(5 * secondsPerHour)
    }

    /// An app session on `clock`, with its own settings store so setting changes stay out of the shared suite.
    private func makeSession(clock: FixedNow) throws -> AppSession {
        let inMemory = try AppEnvironment.inMemory(now: clock)
        let environment = AppEnvironment(
            fileStore: inMemory.fileStore,
            database: inMemory.database,
            now: clock,
            settingsStore: TestSettings.make(),
            sleeper: ImmediateSleeper()
        )
        return AppSession(environment: environment)
    }

    /// A session with one passive card per text (new cards, Normal frequency), two-button layout.
    private func seededSession(texts: [String] = ["One", "Two"]) async throws -> AppSession {
        let session = try makeSession(clock: FixedNow(sessionTime))
        session.settings.showFourRatingButtons = false
        for text in texts {
            _ = try await ReviewTestFixture.seedCard(session.environment, text: text)
        }
        return session
    }

    /// A model with the plan loaded and started.
    private func startedModel(_ session: AppSession) async -> ReviewSessionModel {
        let model = ReviewSessionModel(session: session)
        await model.loadPlan()
        await model.start()
        return model
    }

    /// Every review log row in the database, read back through GRDB.
    private func reviewLogs(_ session: AppSession) async throws -> [ReviewLogEntry] {
        try await session.environment.database.writer.read { db in
            try ReviewLogEntry.fetchAll(db)
        }
    }

    /// Inserts one cloze card (mastery, so it needs a reveal) on its own highlight, due at the base.
    private func seedClozeCard(_ session: AppSession) async throws {
        let env = session.environment
        try await env.categoryRepository.setFrequency(id: BuiltinCategory.lectureSlides.id, .normal)
        let document = TestData.document()
        try await env.documentRepository.insert(document)
        let highlight = TestData.highlight(documentId: document.id, text: "Cloze source")
        try await env.highlightRepository.insert(highlight)
        let cloze = try ReviewCardFactory.mastery(
            highlightId: highlight.id,
            cardType: .cloze,
            clozeRanges: [[0, 5]],
            question: nil,
            answer: "Cloze source",
            now: ReviewTestFixture.base
        )
        try await env.database.writer.write { db in try cloze.insert(db) }
    }

    @Test func planThenStart() async throws {
        // Two cards rated days before the session, so they are due (older first), and one card never rated (new).
        let clock = FixedNow(ReviewTestFixture.base.addingTimeInterval(-12 * secondsPerDay))
        let session = try makeSession(clock: clock)
        defer { ReaderTestSupport.cleanUp(session) }
        let env = session.environment
        let service = ReviewTestFixture.service(env, clock: clock)

        let older = try await ReviewTestFixture.seedCard(env, text: "Older").card
        _ = try await service.rate(cardId: older.id, rating: .good, context: .daily)

        clock.set(ReviewTestFixture.base.addingTimeInterval(-10 * secondsPerDay))
        let newer = try await ReviewTestFixture.seedCard(env, text: "Newer").card
        _ = try await service.rate(cardId: newer.id, rating: .good, context: .daily)

        let fresh = try await ReviewTestFixture.seedCard(env, text: "Fresh").card
        clock.set(sessionTime)

        let model = ReviewSessionModel(session: session)
        #expect(model.phase == .idle)

        await model.loadPlan()
        #expect(model.phase == .ready(dueCount: 2, newCount: 1))
        #expect(model.queue.isEmpty)

        await model.start()
        #expect(model.phase == .reviewing)
        #expect(model.queue.map(\.id) == [older.id, newer.id, fresh.id])
        #expect(model.position == 0)
        #expect(model.current?.id == older.id)
        #expect(model.progressText == "1 of 3")

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func passiveRatesWithoutReveal() async throws {
        let session = try await seededSession(texts: ["Only"])
        defer { ReaderTestSupport.cleanUp(session) }
        let model = await startedModel(session)

        #expect(model.content?.needsReveal == false)
        #expect(model.canRate)

        await model.rate(.good)
        guard case .finished(let summary) = model.phase else {
            Issue.record("Expected the session to finish, got \(model.phase)")
            return
        }
        #expect(summary.reviewed == 1)
        #expect(summary.remembered == 1)
        #expect(summary.rememberedPercent == 100)

        try await session.environment.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func masteryNeedsReveal() async throws {
        let session = try makeSession(clock: FixedNow(sessionTime))
        defer { ReaderTestSupport.cleanUp(session) }
        session.settings.showFourRatingButtons = false
        try await seedClozeCard(session)

        let model = await startedModel(session)
        #expect(model.content?.needsReveal == true)
        #expect(!model.canRate)

        // Before the reveal, no rating key works; only space reveals.
        let ratingKeys: [Character] = ["1", "2", "3", "4", "x"]
        for key in ratingKeys {
            #expect(model.action(forKey: key) == nil, "key \(key) before reveal")
        }
        #expect(model.action(forKey: " ") == .reveal)

        await model.perform(.reveal)
        #expect(model.isRevealed)
        #expect(model.canRate)
        #expect(model.action(forKey: " ") == nil)
        #expect(model.action(forKey: "2") == .rate(.good))

        try await session.environment.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test("keys map to buttons", arguments: reviewKeyCases)
    func keysMapToButtons(_ keyCase: ReviewKeyCase) async throws {
        let session = try await seededSession(texts: ["Only"])
        defer { ReaderTestSupport.cleanUp(session) }
        session.settings.showFourRatingButtons = keyCase.fourButtons
        let model = await startedModel(session)

        #expect(model.action(forKey: keyCase.key) == keyCase.expected)

        try await session.environment.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func performRatesCurrentCard() async throws {
        let session = try await seededSession()
        defer { ReaderTestSupport.cleanUp(session) }
        let model = await startedModel(session)
        let first = try #require(model.queue.first?.id)

        await model.perform(.rate(.good))

        #expect(model.phase == .reviewing)
        #expect(model.queue.count == 1)
        #expect(model.position == 1)
        let logs = try await reviewLogs(session)
        #expect(logs.map(\.cardId) == [first])

        try await session.environment.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func ratingAdvancesAndFinishes() async throws {
        let session = try await seededSession(texts: ["One", "Two", "Three"])
        defer { ReaderTestSupport.cleanUp(session) }
        let model = await startedModel(session)
        let queued = model.queue.map(\.id)
        try #require(queued.count == 3)

        await model.rate(.again)
        #expect(model.phase == .reviewing)
        #expect(model.queue.count == 2)
        #expect(model.position == 1)
        #expect(model.progressText == "2 of 3")

        await model.rate(.good)
        #expect(model.phase == .reviewing)
        #expect(model.position == 2)

        await model.rate(.good)
        guard case .finished(let summary) = model.phase else {
            Issue.record("Expected the session to finish, got \(model.phase)")
            return
        }
        #expect(summary.reviewed == 3)
        #expect(summary.remembered == 2)
        #expect(summary.rememberedPercent == 67)
        #expect(model.current == nil)
        #expect(model.queue.isEmpty)

        let logs = try await reviewLogs(session)
        #expect(logs.count == 3)
        #expect(Set(logs.map(\.cardId)) == Set(queued))
        #expect(logs.map(\.rating).sorted() == [
            ReviewRating.again.rawValue,
            ReviewRating.good.rawValue,
            ReviewRating.good.rawValue,
        ])

        try await session.environment.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func skipMovesCardToEnd() async throws {
        let session = try await seededSession(texts: ["One", "Two", "Three"])
        defer { ReaderTestSupport.cleanUp(session) }
        let model = await startedModel(session)
        let initial = model.queue.map(\.id)
        try #require(initial.count == 3)

        model.skip()

        #expect(model.queue.map(\.id) == Array(initial.dropFirst()) + [initial[0]])
        #expect(model.position == 0)
        let logs = try await reviewLogs(session)
        #expect(logs.isEmpty)

        try await session.environment.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func reloadBeforeSkipCarriesTheNewNote() async throws {
        let session = try await seededSession(texts: ["One", "Two"])
        defer { ReaderTestSupport.cleanUp(session) }
        let env = session.environment
        let model = await startedModel(session)
        let first = try #require(model.queue.first)

        try await env.highlightRepository.updateNote(id: first.highlight.id, note: "Fresh note", at: sessionTime)
        await model.reloadCurrent()
        model.skip()

        #expect(model.queue.last?.id == first.id)
        #expect(model.queue.last?.highlight.note == "Fresh note")

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func missingCardIsDropped() async throws {
        let session = try await seededSession()
        defer { ReaderTestSupport.cleanUp(session) }
        let env = session.environment
        let model = await startedModel(session)
        let doomed = try #require(model.queue.first)
        let kept = try #require(model.queue.last)

        // Deleting the highlight cascades to its card, so the rating fails with cardMissing.
        _ = try await env.highlightRepository.delete(id: doomed.highlight.id, fileStore: env.fileStore)
        await model.rate(.good)

        #expect(model.errorMessage == nil)
        #expect(model.phase == .reviewing)
        #expect(model.position == 0)
        #expect(model.queue.map(\.id) == [kept.id])
        #expect(model.progressText == "1 of 1")

        // The remaining card is rated and the summary counts only that one.
        await model.rate(.good)
        guard case .finished(let summary) = model.phase else {
            Issue.record("Expected the session to finish, got \(model.phase)")
            return
        }
        #expect(summary.reviewed == 1)
        #expect(summary.remembered == 1)

        let logs = try await reviewLogs(session)
        #expect(logs.map(\.cardId) == [kept.id])

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func frequencyOffRemovesCurrentCard() async throws {
        let session = try await seededSession()
        defer { ReaderTestSupport.cleanUp(session) }
        let env = session.environment
        let model = await startedModel(session)
        let first = try #require(model.queue.first?.id)

        await model.setFrequency(.off)

        #expect(model.errorMessage == nil)
        #expect(model.queue.count == 1)
        #expect(model.queue.first?.id != first)

        let stored = try await env.reviewCardRepository.fetch(id: first)
        #expect(stored?.frequencyOverride == .off)
        #expect(stored?.suspended == true)

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func sessionModelIsKeptBySession() async throws {
        let session = try makeSession(clock: FixedNow(sessionTime))
        defer { ReaderTestSupport.cleanUp(session) }

        let first = session.dailyReviewModel()
        #expect(first === session.dailyReviewModel())

        try await session.environment.database.writer.write { db in try FTSIntegrity.check(db) }
    }
}
