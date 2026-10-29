import Foundation
import GRDB
import Testing
@testable import StudyReader

@MainActor
@Suite("FlashcardsModel")
struct FlashcardsModelTests {
    private let r = TestData.referenceDate
    private let day: TimeInterval = 86_400
    private let calendar = ReviewTestFixture.calendar

    private func makeEnv() throws -> AppEnvironment {
        try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
    }

    private func seedDocument(
        _ env: AppEnvironment,
        categoryId: String = BuiltinCategory.lectureSlides.id
    ) async throws -> LibraryDocument {
        let document = TestData.document(categoryId: categoryId)
        try await env.documentRepository.insert(document)
        return document
    }

    /// Inserts a highlight (with `tagIds`) and one card on it, written as given so each test controls the state,
    /// due date, suspension and card type.
    @discardableResult
    private func seedCard(
        _ env: AppEnvironment,
        documentId: String,
        cardId: String = UUID().uuidString,
        cardType: CardType = .passive,
        state: ReviewCardState,
        dueAt: Date? = nil,
        suspended: Bool = false,
        tagIds: [String] = []
    ) async throws -> ReviewCard {
        let highlight = TestData.highlight(documentId: documentId)
        try await env.highlightRepository.insert(highlight, tagIds: tagIds)
        var card = TestData.reviewCard(
            highlightId: highlight.id,
            id: cardId,
            cardType: cardType,
            dueAt: dueAt ?? r,
            state: state
        )
        card.suspended = suspended
        card.suspendedReason = suspended ? .user : nil
        let inserted = card
        try await env.database.writer.write { db in try inserted.insert(db) }
        return card
    }

    /// Waits until the model's list holds exactly `ids`.
    private func waitForIds(_ model: FlashcardsModel, _ ids: Set<String>) async -> Bool {
        await TestWait.until { await Set(model.items.map(\.id)) == ids }
    }

    /// Restarts the observer so it reads the model's current filter, as the view does on a filter change.
    private func restart(_ model: FlashcardsModel, _ observer: inout Task<Void, Never>) {
        observer.cancel()
        observer = Task { await model.observe() }
    }

    @Test func filtersByState() async throws {
        let env = try makeEnv()
        let document = try await seedDocument(env)
        let new = try await seedCard(env, documentId: document.id, state: .new)
        let learning = try await seedCard(env, documentId: document.id, state: .learning, dueAt: r.addingTimeInterval(-day))
        let review = try await seedCard(env, documentId: document.id, state: .review, dueAt: r.addingTimeInterval(day))
        let suspended = try await seedCard(env, documentId: document.id, state: .review, suspended: true)

        let model = FlashcardsModel(environment: env, calendar: calendar)
        var observer = Task { await model.observe() }
        defer { observer.cancel() }
        #expect(await waitForIds(model, [new.id, learning.id, review.id, suspended.id]))

        model.toggle(state: .new)
        restart(model, &observer)
        #expect(await waitForIds(model, [new.id]), "States narrow the list")

        model.clearFilters()
        model.toggle(state: .learning)
        restart(model, &observer)
        #expect(await waitForIds(model, [learning.id]))

        // Two states in one field combine with OR.
        model.toggle(state: .suspended)
        restart(model, &observer)
        #expect(await waitForIds(model, [learning.id, suspended.id]), "Two states combine with OR")

        // Toggling a selected state removes it.
        model.toggle(state: .learning)
        restart(model, &observer)
        #expect(await waitForIds(model, [suspended.id]))

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func filtersByDueDate() async throws {
        let env = try makeEnv()
        let document = try await seedDocument(env)
        _ = try await seedCard(env, documentId: document.id, state: .review, dueAt: r.addingTimeInterval(-day))
        let inWindow = try await seedCard(env, documentId: document.id, state: .review, dueAt: r)
        _ = try await seedCard(env, documentId: document.id, state: .review, dueAt: r.addingTimeInterval(day))

        let model = FlashcardsModel(environment: env, calendar: calendar)
        // Setting a day keeps the start of that day, and the last day is inclusive.
        model.dueFromDay = r
        model.dueToDay = r
        #expect(model.filter.dueFrom == calendar.startOfDay(for: r))
        #expect(model.dueToDay == calendar.startOfDay(for: r))
        #expect(model.filter.dueBefore == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: r)))

        var observer = Task { await model.observe() }
        defer { observer.cancel() }
        #expect(await waitForIds(model, [inWindow.id]))

        model.dueFromDay = nil
        model.dueToDay = nil
        restart(model, &observer)
        #expect(await TestWait.until { await model.items.count == 3 }, "Clearing both days shows every card")

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func filtersCombine() async throws {
        let env = try makeEnv()
        let docA = try await seedDocument(env)
        let docB = try await seedDocument(env, categoryId: BuiltinCategory.paper.id)
        let alpha = try await env.tagRepository.findOrCreate(name: "alpha", at: r).id

        let c1 = try await seedCard(env, documentId: docA.id, state: .review, tagIds: [alpha])
        let c2 = try await seedCard(env, documentId: docA.id, cardType: .cloze, state: .new, tagIds: [alpha])
        let c3 = try await seedCard(env, documentId: docA.id, state: .review)
        let c4 = try await seedCard(env, documentId: docB.id, state: .review, tagIds: [alpha])
        let c5 = try await seedCard(env, documentId: docA.id, state: .review, suspended: true, tagIds: [alpha])
        let all: Set<String> = [c1.id, c2.id, c3.id, c4.id, c5.id]

        let model = FlashcardsModel(environment: env, calendar: calendar)
        var observer = Task { await model.observe() }
        defer { observer.cancel() }
        #expect(await waitForIds(model, all))

        model.toggle(documentId: docA.id)
        model.toggle(tagId: alpha)
        model.toggle(state: .review)
        model.toggle(cardType: .passive)
        #expect(model.isFiltered)
        restart(model, &observer)
        #expect(await waitForIds(model, [c1.id]), "Document, tag, state and type combine with AND")

        model.clearFilters()
        #expect(!model.isFiltered)
        restart(model, &observer)
        #expect(await waitForIds(model, all))

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func editsCards() async throws {
        let env = try makeEnv()
        let (highlight1, card1) = try await ReviewTestFixture.seedCard(env, text: "Original")
        let (highlight2, passive2) = try await ReviewTestFixture.seedCard(env, text: "Second")

        let model = FlashcardsModel(environment: env, calendar: calendar)
        let observer = Task { await model.observe() }
        defer { observer.cancel() }
        #expect(await waitForIds(model, [card1.id, passive2.id]))

        // Frequency Off suspends the selected card; the row stays in the list.
        model.selection = card1.id
        await model.setFrequency(.off)
        let suspended = await TestWait.until {
            await model.items.first { $0.id == card1.id }?.state == .suspended
        }
        #expect(suspended, "Off suspends the card")

        // Editing the highlight text changes the card front and marks it edited.
        await model.editHighlightText("New")
        let edited = await TestWait.until {
            await model.selectedContent?.front == ReviewCardContent.Body.markdown("New")
        }
        #expect(edited, "The edited text shows on the card")
        #expect(model.selectedContent?.isEdited == true)
        #expect(highlight1.id == model.selectedItem?.item.highlight.id)

        // A Q&A card from Mastery shows its answer on the back.
        let qaDraft = MasteryDraft(id: UUID().uuidString, isSaved: false, kind: .qa(question: "Q?", answer: "Answer"))
        try await env.masteryService.save([qaDraft], highlightId: highlight2.id)
        let qaAppeared = await TestWait.until { await model.items.contains { $0.item.card.cardType == .qa } }
        #expect(qaAppeared)
        let qaCard = try #require(model.items.first { $0.item.card.cardType == .qa })
        model.selection = qaCard.id
        #expect(model.selectedContent?.back == ReviewCardContent.Body.markdown("Answer"))

        // Saving the Q&A card again updates its answer.
        let savedDraft = MasteryDraft(id: qaCard.id, isSaved: true, kind: .qa(question: "Q?", answer: "Answer changed"))
        try await env.masteryService.save([savedDraft], highlightId: highlight2.id)
        let changed = await TestWait.until {
            await model.selectedContent?.back == ReviewCardContent.Body.markdown("Answer changed")
        }
        #expect(changed, "The saved Q&A answer is shown after the edit")
        #expect(model.errorMessage == nil)

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func selectionIsPrunedAndCountText() async throws {
        let env = try makeEnv()
        let (highlight, card) = try await ReviewTestFixture.seedCard(env, text: "Gone soon")

        let model = FlashcardsModel(environment: env, calendar: calendar)
        let observer = Task { await model.observe() }
        defer { observer.cancel() }
        #expect(await TestWait.until { await model.items.count == 1 })

        model.selection = card.id
        #expect(model.selectedItem?.id == card.id)

        try await env.highlightService.delete(ids: [highlight.id])
        let emptied = await TestWait.until { await model.items.isEmpty }
        #expect(emptied)
        #expect(model.selection == nil, "A selection whose card vanished is cleared")
        #expect(model.selectedItem == nil)

        #expect(FlashcardsModel.countText(1) == "1 card")
        #expect(FlashcardsModel.countText(3) == "3 cards")

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func staleRunIsIgnored() async throws {
        let env = try makeEnv()
        let document = try await seedDocument(env)
        let newCard = try await seedCard(env, documentId: document.id, state: .new)
        let reviewCard = try await seedCard(env, documentId: document.id, state: .review)

        let model = FlashcardsModel(environment: env, calendar: calendar)

        // Run 1 watches the new-state filter.
        model.toggle(state: .new)
        let first = Task { await model.observe() }
        defer { first.cancel() }
        #expect(await waitForIds(model, [newCard.id]))

        // Run 2 replaces it with the review-state filter. Run 1 is not cancelled, so it stays alive and can emit.
        model.toggle(state: .new)
        model.toggle(state: .review)
        let second = Task { await model.observe() }
        defer { second.cancel() }
        #expect(await waitForIds(model, [reviewCard.id]))

        // A new-state card makes run 1 emit a stale list. The model must ignore it.
        _ = try await seedCard(env, documentId: document.id, state: .new)
        try await Task.sleep(for: .milliseconds(200))
        #expect(Set(model.items.map(\.id)) == [reviewCard.id], "A superseded run must not overwrite the list")

        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }
}
