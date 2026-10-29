import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("MasteryCardWrites")
struct MasteryCardWriteTests {
    /// Inserts a document in `categoryId`, one highlight in it and its passive card.
    private func seed(
        _ database: AppDatabase,
        categoryId: String = BuiltinCategory.lectureSlides.id
    ) async throws -> (highlight: Highlight, passive: ReviewCard) {
        let document = TestData.document(categoryId: categoryId)
        try await DocumentRepository(database: database).insert(document)
        let highlight = TestData.highlight(documentId: document.id)
        try await HighlightRepository(database: database).insert(highlight)
        let passive = try ReviewCardFactory.passive(highlightId: highlight.id, now: TestData.referenceDate)
        try await ReviewCardRepository(database: database).insertPassiveCards([passive])
        return (highlight, passive)
    }

    private func cloze(highlightId: String, answer: String = "Sample highlight") throws -> ReviewCard {
        try ReviewCardFactory.mastery(
            highlightId: highlightId,
            cardType: .cloze,
            clozeRanges: [[0, 6]],
            question: nil,
            answer: answer,
            now: TestData.referenceDate
        )
    }

    private func qa(highlightId: String) throws -> ReviewCard {
        try ReviewCardFactory.mastery(
            highlightId: highlightId,
            cardType: .qa,
            clozeRanges: nil,
            question: "What is it?",
            answer: "A sample",
            now: TestData.referenceDate
        )
    }

    private func setCategoryFrequency(_ database: AppDatabase, id: String, _ frequency: ReviewFrequency) async throws {
        try await CategoryRepository(database: database).setFrequency(id: id, frequency)
    }

    @Test func insertSuspendsPassive() async throws {
        let database = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: database)
        let (highlight, passive) = try await seed(database)
        let before = try #require(try await repo.fetch(id: passive.id))
        #expect(before.suspended == false)

        let clozeCard = try cloze(highlightId: highlight.id)
        let qaCard = try qa(highlightId: highlight.id)
        try await repo.insertMasteryCards([clozeCard, qaCard], highlightId: highlight.id)

        let storedPassive = try #require(try await repo.fetch(id: passive.id))
        #expect(storedPassive.suspended == true)
        #expect(storedPassive.suspendedReason == .mastery)

        let storedCloze = try #require(try await repo.fetch(id: clozeCard.id))
        let storedQA = try #require(try await repo.fetch(id: qaCard.id))
        #expect(storedCloze.suspended == false)
        #expect(storedCloze.suspendedReason == nil)
        #expect(storedQA.suspended == false)
        #expect(storedQA.suspendedReason == nil)
        try await database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func deleteLastRestoresPassive() async throws {
        let database = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: database)
        let (highlight, passive) = try await seed(database)
        let clozeCard = try cloze(highlightId: highlight.id)
        let qaCard = try qa(highlightId: highlight.id)
        try await repo.insertMasteryCards([clozeCard, qaCard], highlightId: highlight.id)

        let deletedQA = try await repo.deleteMasteryCard(id: qaCard.id)
        #expect(deletedQA)
        let afterQA = try #require(try await repo.fetch(id: passive.id))
        #expect(afterQA.suspendedReason == .mastery)

        let deletedCloze = try await repo.deleteMasteryCard(id: clozeCard.id)
        #expect(deletedCloze)
        let restored = try #require(try await repo.fetch(id: passive.id))
        #expect(restored.suspended == false)
        #expect(restored.suspendedReason == nil)
        try await database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func deleteLastWithCategoryOffIsFrequencyOff() async throws {
        let database = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: database)
        let (highlight, passive) = try await seed(database)
        let clozeCard = try cloze(highlightId: highlight.id)
        let qaCard = try qa(highlightId: highlight.id)
        try await repo.insertMasteryCards([clozeCard, qaCard], highlightId: highlight.id)

        try await repo.deleteMasteryCard(id: qaCard.id)
        try await setCategoryFrequency(database, id: BuiltinCategory.lectureSlides.id, .off)
        try await repo.deleteMasteryCard(id: clozeCard.id)

        let restored = try #require(try await repo.fetch(id: passive.id))
        #expect(restored.suspended == true)
        #expect(restored.suspendedReason == .frequencyOff)
        try await database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func insertChecks() async throws {
        let database = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: database)
        let (highlight, passive) = try await seed(database)
        let otherDocument = TestData.document()
        try await DocumentRepository(database: database).insert(otherDocument)
        let otherHighlight = TestData.highlight(documentId: otherDocument.id)
        try await HighlightRepository(database: database).insert(otherHighlight)

        func countCards() async throws -> Int {
            try await database.writer.read { db in try ReviewCard.fetchCount(db) }
        }
        let initialCount = try await countCards()

        // A passive card in the list.
        let anotherPassive = try ReviewCardFactory.passive(highlightId: highlight.id, now: TestData.referenceDate)
        await #expect(throws: ReviewCardError.notMasteryCard) {
            try await repo.insertMasteryCards([anotherPassive], highlightId: highlight.id)
        }
        #expect(try await countCards() == initialCount)

        // A card of another highlight.
        let foreign = try cloze(highlightId: otherHighlight.id)
        await #expect(throws: ReviewCardError.highlightMismatch) {
            try await repo.insertMasteryCards([foreign], highlightId: highlight.id)
        }
        #expect(try await countCards() == initialCount)

        // An unknown highlight.
        let orphan = try cloze(highlightId: "missing")
        await #expect(throws: RepositoryError.notFound) {
            try await repo.insertMasteryCards([orphan], highlightId: "missing")
        }
        #expect(try await countCards() == initialCount)

        let stored = try await repo.cards(forHighlight: highlight.id)
        #expect(stored.map(\.id) == [passive.id])
        #expect(stored.first?.suspended == false)
        try await database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func updateKeepsSchedule() async throws {
        let database = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: database)
        let (highlight, passive) = try await seed(database)
        let clozeCard = try cloze(highlightId: highlight.id)
        try await repo.insertMasteryCards([clozeCard], highlightId: highlight.id)

        let reviewedAt = TestData.referenceDate.addingTimeInterval(60)
        let rating = RatingWrite(
            cardId: clozeCard.id,
            fsrsCard: "{\"reps\":1}",
            dueAt: TestData.referenceDate.addingTimeInterval(600),
            state: .learning,
            reviewedAt: reviewedAt,
            rating: .good,
            sessionKind: .daily,
            themedReviewId: nil,
            fsrsLog: "{\"rating\":3}"
        )
        try await repo.recordRating(rating)
        let before = try #require(try await repo.fetch(id: clozeCard.id))

        try await repo.updateMasteryCard(
            id: clozeCard.id,
            clozeRanges: [[0, 9]],
            question: nil,
            answer: "Edited answer"
        )

        let after = try #require(try await repo.fetch(id: clozeCard.id))
        #expect(after.clozeRanges == [[0, 9]])
        #expect(after.answer == "Edited answer")
        #expect(after.fsrsCard == before.fsrsCard)
        #expect(after.dueAt == before.dueAt)
        #expect(after.state == before.state)
        #expect(after.introducedAt == before.introducedAt)
        #expect(after.introducedAt == reviewedAt)

        let logCount = try await database.writer.read { db in
            try ReviewLogEntry.filter(Column("cardId") == clozeCard.id).fetchCount(db)
        }
        #expect(logCount == 1)

        await #expect(throws: ReviewCardError.notMasteryCard) {
            try await repo.updateMasteryCard(id: passive.id, clozeRanges: nil, question: nil, answer: "x")
        }
        await #expect(throws: RepositoryError.notFound) {
            try await repo.updateMasteryCard(id: "missing", clozeRanges: nil, question: nil, answer: "x")
        }
        try await database.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func deleteRejectsPassive() async throws {
        let database = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: database)
        let (_, passive) = try await seed(database)

        await #expect(throws: ReviewCardError.notMasteryCard) {
            try await repo.deleteMasteryCard(id: passive.id)
        }
        #expect(try await repo.fetch(id: passive.id) != nil)

        let removed = try await repo.deleteMasteryCard(id: "missing")
        #expect(removed == false)
        try await database.writer.write { db in try FTSIntegrity.check(db) }
    }
}
