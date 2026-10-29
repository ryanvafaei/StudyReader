import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("ReviewCardActionWrites")
struct ReviewCardActionWriteTests {
    /// Inserts a document in `categoryId`, one highlight in it and, when `withCard`, its passive card.
    private func seed(
        _ database: AppDatabase,
        categoryId: String = BuiltinCategory.lectureSlides.id,
        withCard: Bool = true
    ) async throws -> (highlight: Highlight, card: ReviewCard?) {
        let document = TestData.document(categoryId: categoryId)
        try await DocumentRepository(database: database).insert(document)
        let highlight = TestData.highlight(documentId: document.id)
        try await HighlightRepository(database: database).insert(highlight)
        guard withCard else { return (highlight, nil) }
        let card = try ReviewCardFactory.passive(highlightId: highlight.id, now: TestData.referenceDate)
        try await ReviewCardRepository(database: database).insertPassiveCards([card])
        return (highlight, card)
    }

    @Test func overrideOffSuspendsAsUser() async throws {
        let database = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: database)
        let (_, card) = try await seed(database)
        let cardId = try #require(card?.id)

        try await repo.updateFrequencyOverride(cardId: cardId, override: .off, rescheduled: nil)
        var stored = try #require(try await repo.fetch(id: cardId))
        #expect(stored.frequencyOverride == .off)
        #expect(stored.suspended == true)
        #expect(stored.suspendedReason == .user)

        try await repo.updateFrequencyOverride(cardId: cardId, override: .high, rescheduled: nil)
        stored = try #require(try await repo.fetch(id: cardId))
        #expect(stored.frequencyOverride == .high)
        #expect(stored.suspended == false)
        #expect(stored.suspendedReason == nil)

        try await repo.updateFrequencyOverride(cardId: cardId, override: nil, rescheduled: nil)
        stored = try #require(try await repo.fetch(id: cardId))
        #expect(stored.frequencyOverride == nil)
        #expect(stored.suspended == false)
        #expect(stored.suspendedReason == nil)
        try await database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func overrideHighInOffCategoryUnsuspends() async throws {
        let database = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: database)
        try await CategoryRepository(database: database).setFrequency(id: BuiltinCategory.notes.id, .off)
        let (_, card) = try await seed(database, categoryId: BuiltinCategory.notes.id)
        let cardId = try #require(card?.id)

        var stored = try #require(try await repo.fetch(id: cardId))
        #expect(stored.suspendedReason == .frequencyOff)

        try await repo.updateFrequencyOverride(cardId: cardId, override: .high, rescheduled: nil)
        stored = try #require(try await repo.fetch(id: cardId))
        #expect(stored.frequencyOverride == .high)
        #expect(stored.suspended == false)
        #expect(stored.suspendedReason == nil)
        try await database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func rescheduledStateIsStored() async throws {
        let database = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: database)
        let (_, card) = try await seed(database)
        let original = try #require(card)

        let newDue = TestData.referenceDate.addingTimeInterval(86_400)
        let rescheduled = RescheduledCard(fsrsCard: "{\"due\":86400}", dueAt: newDue)
        try await repo.updateFrequencyOverride(cardId: original.id, override: .low, rescheduled: rescheduled)
        var stored = try #require(try await repo.fetch(id: original.id))
        #expect(stored.fsrsCard == rescheduled.fsrsCard)
        #expect(stored.dueAt == newDue)
        #expect(stored.frequencyOverride == .low)

        try await repo.updateFrequencyOverride(cardId: original.id, override: nil, rescheduled: nil)
        stored = try #require(try await repo.fetch(id: original.id))
        #expect(stored.fsrsCard == rescheduled.fsrsCard)
        #expect(stored.dueAt == newDue)
        #expect(stored.frequencyOverride == nil)

        await #expect(throws: RepositoryError.notFound) {
            try await repo.updateFrequencyOverride(cardId: "missing", override: .off, rescheduled: nil)
        }
        try await database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func editedTextRules() async throws {
        let database = try AppDatabase.makeInMemory()
        let repo = HighlightRepository(database: database)
        let (highlight, _) = try await seed(database, withCard: false)
        let editDate = TestData.referenceDate.addingTimeInterval(60)

        try await repo.updateEditedText(id: highlight.id, editedText: "New wording", at: editDate)
        var stored = try #require(try await repo.fetch(id: highlight.id))
        #expect(stored.editedText == "New wording")
        #expect(stored.updatedAt == editDate)

        try await repo.updateEditedText(id: highlight.id, editedText: "  ", at: editDate)
        stored = try #require(try await repo.fetch(id: highlight.id))
        #expect(stored.editedText == nil)

        try await repo.updateEditedText(id: highlight.id, editedText: "New wording", at: editDate)
        try await repo.updateEditedText(id: highlight.id, editedText: highlight.text, at: editDate)
        stored = try #require(try await repo.fetch(id: highlight.id))
        #expect(stored.editedText == nil)

        #expect(stored.text == highlight.text)
        #expect(stored.richText == highlight.richText)
        #expect(stored.anchor == highlight.anchor)

        await #expect(throws: RepositoryError.notFound) {
            try await repo.updateEditedText(id: "missing", editedText: "x", at: editDate)
        }
        try await database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func editedTextIsSearchable() async throws {
        let env = try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))
        let document = TestData.document()
        try await env.documentRepository.insert(document)
        let highlight = TestData.highlight(documentId: document.id)
        try await env.highlightRepository.insert(highlight)

        try await env.highlightRepository.updateEditedText(
            id: highlight.id,
            editedText: "photosynthesis basics",
            at: TestData.referenceDate.addingTimeInterval(60)
        )

        let results = try await env.searchService.search("photosynthesis")
        #expect(results.highlights.map(\.highlightId) == [highlight.id])
        try await env.database.writer.write { db in try FTSIntegrity.check(db) }
    }
}
