import Foundation
import Testing
@testable import StudyReader

@MainActor
@Suite("ThemedReviewsModel")
struct ThemedReviewsModelTests {
    private let calendar = ReviewTestFixture.calendar
    /// 05:00 on the reference day, after the 04:00 review-day boundary.
    private var now: Date { ReviewTestFixture.base.addingTimeInterval(5 * 3_600) }

    private func makeSession() throws -> AppSession {
        let inMemory = try AppEnvironment.inMemory(now: FixedNow(now))
        let environment = AppEnvironment(
            fileStore: inMemory.fileStore,
            database: inMemory.database,
            now: FixedNow(now),
            settingsStore: TestSettings.make(),
            sleeper: ImmediateSleeper()
        )
        return AppSession(environment: environment)
    }

    /// Runs `observe()` until the first snapshot arrived, then stops it.
    private func load(_ model: ThemedReviewsModel) async {
        let task = Task { await model.observe() }
        while !model.hasLoaded { await Task.yield() }
        task.cancel()
    }

    private func review(_ interval: ReviewInterval, name: String = "Exam") -> ThemedReview {
        ThemedReview(id: "r", name: name, interval: interval, createdAt: ReviewTestFixture.base)
    }

    @Test func listAndDue() async throws {
        let session = try makeSession()
        let repository = session.environment.themedReviewRepository
        let never = try await repository.create(ThemedReviewDraft(name: "Zeta"), at: now)
        let done = try await repository.create(ThemedReviewDraft(name: "Alpha"), at: now)
        try await repository.markCompleted(id: done.id, at: now)

        let model = ThemedReviewsModel(session: session, calendar: calendar)
        await load(model)

        #expect(model.reviews.map(\.name) == ["Alpha", "Zeta"])
        let fetchedDone = try #require(model.reviews.first { $0.id == done.id })
        let fetchedNever = try #require(model.reviews.first { $0.id == never.id })
        #expect(model.isDue(fetchedNever))
        #expect(!model.isDue(fetchedDone))
    }

    @Test func intervalSummaries() throws {
        let model = ThemedReviewsModel(session: try makeSession(), calendar: calendar)
        let symbols = calendar.shortWeekdaySymbols
        let cases: [(ReviewInterval, String)] = [
            (.daily, "Every day"),
            (.everyNDays(1), "Every day"),
            (.everyNDays(3), "Every 3 days"),
            (.weekdays([5, 2]), "\(symbols[1]), \(symbols[4])"),
        ]
        for (interval, expected) in cases {
            #expect(model.intervalSummary(review(interval)) == expected)
        }
    }

    @Test func duplicateAndDelete() async throws {
        let session = try makeSession()
        let original = try await session.environment.themedReviewRepository.create(ThemedReviewDraft(name: "Exam"), at: now)
        let model = ThemedReviewsModel(session: session, calendar: calendar)
        await load(model)

        await model.duplicate(original.id)
        let copyId = try #require(model.selection)
        #expect(copyId != original.id)
        let copy = try #require(try await session.environment.themedReviewRepository.fetch(id: copyId))
        #expect(copy.name == "Exam copy")

        await model.delete(copyId)
        #expect(model.selection == nil)
        #expect(try await session.environment.themedReviewRepository.fetch(id: copyId) == nil)
    }

    @Test func runCreatesAThemedSession() async throws {
        let session = try makeSession()
        let environment = session.environment
        try await environment.categoryRepository.setFrequency(id: BuiltinCategory.lectureSlides.id, .normal)
        let document = TestData.document()
        try await environment.documentRepository.insert(document)
        let highlight = TestData.highlight(documentId: document.id, text: "A highlight")
        try await environment.highlightRepository.insert(highlight)
        let card = try ReviewCardFactory.passive(highlightId: highlight.id, now: ReviewTestFixture.base)
        try await environment.reviewCardRepository.insertPassiveCards([card])
        let created = try await environment.themedReviewRepository.create(ThemedReviewDraft(name: "Exam"), at: now)
        let model = ThemedReviewsModel(session: session, calendar: calendar)

        await model.run(created.id)
        let running = try #require(model.runningSession)
        #expect(running.phase == .ready(dueCount: 1, newCount: 0))
        #expect(running.themedReviewName == "Exam")

        model.stopRunning()
        #expect(model.runningSession == nil)
        let stored = try #require(try await session.environment.themedReviewRepository.fetch(id: created.id))
        #expect(stored.lastCompletedAt == nil)
    }

    @Test func editorRequestIds() {
        #expect(ThemedEditorRequest.new.id == "new")
        #expect(ThemedEditorRequest.edit("x").id == "x")
        #expect(ThemedEditorRequest.edit("x").reviewId == "x")
        #expect(ThemedEditorRequest.new.reviewId == nil)
    }
}
