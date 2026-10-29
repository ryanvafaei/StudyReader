import Foundation
import Testing
@testable import StudyReader

@MainActor
@Suite("ThemedReviewEditorModel")
struct ThemedReviewEditorModelTests {
    private let calendar = ReviewTestFixture.calendar

    private func makeEnvironment() throws -> AppEnvironment {
        try AppEnvironment.inMemory(now: FixedNow(ReviewTestFixture.base.addingTimeInterval(5 * 3_600)))
    }

    private func makeModel(_ environment: AppEnvironment, reviewId: String? = nil) -> ThemedReviewEditorModel {
        ThemedReviewEditorModel(reviewId: reviewId, environment: environment, calendar: calendar)
    }

    @Test("A new review saves with the chosen values")
    func newReviewSaves() async throws {
        let environment = try makeEnvironment()
        let tag = try await environment.tagRepository.findOrCreate(name: "exam", at: environment.now())
        let model = makeModel(environment)
        await model.load()
        #expect(model.hasLoaded)

        model.draft.name = "Exam week"
        model.toggle(tagId: tag.id)
        model.draft.cardsPerSession = 30
        model.intervalKind = .everyNDays
        model.everyNDays = 3
        model.draft.orderMode = .random

        #expect(await model.save())
        let reviews = try await environment.themedReviewRepository.fetchAll()
        #expect(reviews.count == 1)
        let review = try #require(reviews.first)
        #expect(review.name == "Exam week")
        #expect(review.filter.tagIds == [tag.id])
        #expect(review.cardsPerSession == 30)
        #expect(review.interval == .everyNDays(3))
        #expect(review.orderMode == .random)
        #expect(model.errorMessage == nil)
    }

    @Test("An existing review loads and updates without touching lastCompletedAt")
    func editLoadsAndUpdates() async throws {
        let environment = try makeEnvironment()
        let repository = environment.themedReviewRepository
        let created = try await repository.create(
            ThemedReviewDraft(name: "Old", cardsPerSession: 10, interval: .weekdays([2, 4])),
            at: environment.now()
        )
        let completedAt = environment.now().addingTimeInterval(60)
        try await repository.markCompleted(id: created.id, at: completedAt)

        let model = makeModel(environment, reviewId: created.id)
        await model.load()
        #expect(model.draft.name == "Old")
        #expect(model.draft.cardsPerSession == 10)
        #expect(model.draft.interval == .weekdays([2, 4]))

        model.draft.name = "New"
        #expect(await model.save())
        let stored = try #require(try await repository.fetch(id: created.id))
        #expect(stored.name == "New")
        #expect(stored.lastCompletedAt == completedAt.storageRounded)
        #expect(try await repository.fetchAll().count == 1)
    }

    @Test("Toggles add and remove; interval kinds start from their defaults")
    func togglesAndIntervalKinds() async throws {
        let environment = try makeEnvironment()
        let model = makeModel(environment)

        model.toggle(tagId: "a")
        model.toggle(tagId: "b")
        #expect(model.draft.filter.tagIds == ["a", "b"])
        model.toggle(tagId: "a")
        #expect(model.draft.filter.tagIds == ["b"])
        model.toggle(color: .pink)
        model.toggle(color: .pink)
        #expect(model.draft.filter.colors.isEmpty)
        model.toggle(documentId: "d")
        model.toggle(categoryId: "c")
        #expect(model.draft.filter.documentIds == ["d"])
        #expect(model.draft.filter.categoryIds == ["c"])

        let today = calendar.component(.weekday, from: environment.now())
        model.intervalKind = .weekdays
        #expect(model.draft.interval == .weekdays([today]))
        let other = today == 7 ? 1 : today + 1
        model.toggle(weekday: other)
        #expect(model.draft.interval == .weekdays([today, other].sorted()))
        model.toggle(weekday: other)
        #expect(model.draft.interval == .weekdays([today]))

        model.intervalKind = .everyNDays
        #expect(model.everyNDays == 1)
        #expect(model.draft.interval == .everyNDays(1))
        model.everyNDays = 1_000
        #expect(model.everyNDays == 365)

        model.intervalKind = .daily
        #expect(model.draft.interval == .daily)
    }

    @Test("Weekday toggles follow the calendar's first weekday")
    func weekdayOrderFollowsFirstWeekday() throws {
        var monday = calendar
        monday.firstWeekday = 2
        let model = ThemedReviewEditorModel(reviewId: nil, environment: try makeEnvironment(), calendar: monday)
        #expect(model.weekdayOrder == [2, 3, 4, 5, 6, 7, 1])
    }

    @Test("Empty names can't be saved; no weekdays shows the interval error")
    func errorsShow() async throws {
        let environment = try makeEnvironment()
        let model = makeModel(environment)
        model.draft.name = "   "
        #expect(!model.canSave)
        #expect(await model.save() == false)

        model.draft.name = "Valid"
        #expect(model.canSave)
        model.intervalKind = .weekdays
        let today = calendar.component(.weekday, from: environment.now())
        model.toggle(weekday: today)
        #expect(await model.save() == false)
        #expect(model.errorMessage == ThemedReviewError.invalidInterval.errorDescription)
        #expect(try await environment.themedReviewRepository.fetchAll().isEmpty)
    }
}
