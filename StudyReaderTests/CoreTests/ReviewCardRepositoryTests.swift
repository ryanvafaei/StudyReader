import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("ReviewCardRepository")
struct ReviewCardRepositoryTests {
    /// Inserts a document in `categoryId` and one highlight in it.
    private func seedHighlight(
        _ database: AppDatabase,
        categoryId: String = BuiltinCategory.lectureSlides.id
    ) async throws -> Highlight {
        let document = TestData.document(categoryId: categoryId)
        try await DocumentRepository(database: database).insert(document)
        let highlight = TestData.highlight(documentId: document.id)
        try await HighlightRepository(database: database).insert(highlight)
        return highlight
    }

    /// Sets a category's frequency and/or autoCreateCards with a column-limited update (ADR-0013).
    private func setCategory(
        _ database: AppDatabase,
        id: String,
        frequency: ReviewFrequency? = nil,
        autoCreateCards: Bool? = nil
    ) async throws {
        try await database.writer.write { db in
            var category = try #require(try DocumentCategory.fetchOne(db, key: id))
            var columns: [String] = []
            if let frequency {
                category.frequency = frequency
                columns.append("frequency")
            }
            if let autoCreateCards {
                category.autoCreateCards = autoCreateCards
                columns.append("autoCreateCards")
            }
            try category.update(db, columns: columns)
        }
    }

    @Test func fetchAndOrder() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: db)
        let highlight = try await seedHighlight(db)
        let now = TestData.referenceDate

        let qa = try ReviewCardFactory.mastery(
            highlightId: highlight.id, cardType: .qa, clozeRanges: nil,
            question: "Q", answer: "A", now: now.addingTimeInterval(1)
        )
        let passive = try ReviewCardFactory.passive(highlightId: highlight.id, now: now.addingTimeInterval(2))
        let cloze = try ReviewCardFactory.mastery(
            highlightId: highlight.id, cardType: .cloze, clozeRanges: [[0, 4]],
            question: nil, answer: nil, now: now
        )
        try await db.writer.write { db in
            try qa.insert(db)
            try passive.insert(db)
            try cloze.insert(db)
        }

        let cards = try await repo.cards(forHighlight: highlight.id)
        #expect(cards.map(\.id) == [passive.id, cloze.id, qa.id])
        #expect(cards.map(\.cardType) == [.passive, .cloze, .qa])
        #expect(try await repo.fetch(id: passive.id)?.cardType == .passive)
        #expect(try await repo.fetch(id: cloze.id)?.clozeRanges == [[0, 4]])
        #expect(try await repo.fetch(id: qa.id)?.answer == "A")
        #expect(try await repo.fetch(id: "99999999-0000-0000-0000-000000000000") == nil)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func observeCardsEmitsOnInsert() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: db)
        let highlight = try await seedHighlight(db)
        var iterator = repo.observeCards(forHighlight: highlight.id).makeAsyncIterator()

        let initial = try await iterator.next()
        #expect(initial == [])

        let card = try ReviewCardFactory.passive(highlightId: highlight.id, now: TestData.referenceDate)
        #expect(try await repo.insertPassiveCards([card]) == 1)

        let updated = try #require(try await iterator.next())
        #expect(updated.map(\.id) == [card.id])
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func bulkInsertSkipsHighlightsWithCards() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: db)
        let now = TestData.referenceDate
        let first = try await seedHighlight(db)
        let withQA = try await seedHighlight(db)
        let third = try await seedHighlight(db)
        let unknownHighlightId = "99999999-0000-0000-0000-00000000aaaa"

        let qa = try ReviewCardFactory.mastery(
            highlightId: withQA.id, cardType: .qa, clozeRanges: nil,
            question: "Q", answer: "A", now: now
        )
        try await db.writer.write { db in try qa.insert(db) }

        let inserted = try await repo.insertPassiveCards([
            try ReviewCardFactory.passive(highlightId: first.id, now: now),
            try ReviewCardFactory.passive(highlightId: withQA.id, now: now),
            try ReviewCardFactory.passive(highlightId: third.id, now: now),
            try ReviewCardFactory.passive(highlightId: unknownHighlightId, now: now),
        ])
        #expect(inserted == 2)

        let qaHighlightCards = try await repo.cards(forHighlight: withQA.id)
        #expect(qaHighlightCards.map(\.cardType) == [.qa])
        #expect(try await repo.cards(forHighlight: first.id).count == 1)
        #expect(try await repo.cards(forHighlight: third.id).count == 1)

        // A non-passive card anywhere in the list rejects the whole call and writes nothing.
        let fourth = try await seedHighlight(db)
        let cloze = try ReviewCardFactory.mastery(
            highlightId: fourth.id, cardType: .cloze, clozeRanges: [[0, 2]],
            question: nil, answer: nil, now: now
        )
        await #expect(throws: ReviewCardError.notPassive) {
            try await repo.insertPassiveCards([
                try ReviewCardFactory.passive(highlightId: fourth.id, now: now),
                cloze,
            ])
        }
        #expect(try await repo.cards(forHighlight: fourth.id).isEmpty)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func bulkInsertInOffCategoryIsSuspended() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: db)
        try await setCategory(db, id: BuiltinCategory.notes.id, frequency: .off)
        let highlight = try await seedHighlight(db, categoryId: BuiltinCategory.notes.id)

        let card = try ReviewCardFactory.passive(highlightId: highlight.id, now: TestData.referenceDate)
        #expect(try await repo.insertPassiveCards([card]) == 1)

        let stored = try #require(try await repo.fetch(id: card.id))
        #expect(stored.suspended == true)
        #expect(stored.suspendedReason == .frequencyOff)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func automaticInsertRespectsCategory() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: db)
        let lectures = BuiltinCategory.lectureSlides.id
        try await setCategory(db, id: lectures, frequency: .high, autoCreateCards: true)
        let now = TestData.referenceDate

        let enabled = try await seedHighlight(db, categoryId: lectures)
        let autoOff = try await seedHighlight(db, categoryId: lectures)
        let frequencyOff = try await seedHighlight(db, categoryId: lectures)

        // Enabled category: inserted and stored.
        let card = try ReviewCardFactory.passive(highlightId: enabled.id, now: now)
        let inserted = try await db.writer.write { db in
            try ReviewCardRepository.insertAutomaticPassiveCard(card, db)
        }
        #expect(inserted == true)
        #expect(try await repo.fetch(id: card.id) != nil)

        // Same highlight again: it already has a card, so nothing is inserted.
        let duplicate = try ReviewCardFactory.passive(highlightId: enabled.id, now: now)
        let duplicateInserted = try await db.writer.write { db in
            try ReviewCardRepository.insertAutomaticPassiveCard(duplicate, db)
        }
        #expect(duplicateInserted == false)
        #expect(try await repo.cards(forHighlight: enabled.id).count == 1)

        // autoCreateCards off: nothing inserted.
        try await setCategory(db, id: lectures, autoCreateCards: false)
        let autoOffCard = try ReviewCardFactory.passive(highlightId: autoOff.id, now: now)
        let autoOffInserted = try await db.writer.write { db in
            try ReviewCardRepository.insertAutomaticPassiveCard(autoOffCard, db)
        }
        #expect(autoOffInserted == false)
        #expect(try await repo.cards(forHighlight: autoOff.id).isEmpty)

        // Frequency off: nothing inserted, even with autoCreateCards on.
        try await setCategory(db, id: lectures, frequency: .off, autoCreateCards: true)
        let offCard = try ReviewCardFactory.passive(highlightId: frequencyOff.id, now: now)
        let offInserted = try await db.writer.write { db in
            try ReviewCardRepository.insertAutomaticPassiveCard(offCard, db)
        }
        #expect(offInserted == false)
        #expect(try await repo.cards(forHighlight: frequencyOff.id).isEmpty)

        // Only passive cards may be inserted automatically.
        try await setCategory(db, id: lectures, frequency: .high)
        let cloze = try ReviewCardFactory.mastery(
            highlightId: autoOff.id, cardType: .cloze, clozeRanges: [[0, 1]],
            question: nil, answer: nil, now: now
        )
        #expect(throws: ReviewCardError.notPassive) {
            try db.writer.write { db in
                _ = try ReviewCardRepository.insertAutomaticPassiveCard(cloze, db)
            }
        }
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func recomputeAppliesTheRule() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: db)
        let lectures = BuiltinCategory.lectureSlides.id
        let now = TestData.referenceDate

        let highlight = try await seedHighlight(db, categoryId: lectures)
        let passive = try ReviewCardFactory.passive(highlightId: highlight.id, now: now)
        let cloze = try ReviewCardFactory.mastery(
            highlightId: highlight.id, cardType: .cloze, clozeRanges: [[0, 1]],
            question: nil, answer: nil, now: now
        )
        try await db.writer.write { db in
            try passive.insert(db)
            try cloze.insert(db)
        }

        // The cloze card makes the passive card a Mastery suspension.
        let changedByHighlight = try await db.writer.write { db in
            try ReviewSuspension.recompute(highlightIds: [highlight.id], db)
        }
        #expect(changedByHighlight == 1)
        let passiveAfterMastery = try #require(try await repo.fetch(id: passive.id))
        #expect(passiveAfterMastery.suspended == true)
        #expect(passiveAfterMastery.suspendedReason == .mastery)
        #expect(try await repo.fetch(id: cloze.id)?.suspended == false)

        // A card-level override of off suspends the cloze card with reason .user.
        try await db.writer.write { db in
            var overridden = try #require(try ReviewCard.fetchOne(db, key: cloze.id))
            overridden.frequencyOverride = .off
            try overridden.update(db, columns: ["frequencyOverride"])
        }
        let changedByDocument = try await db.writer.write { db in
            try ReviewSuspension.recompute(documentIds: [highlight.documentId], db)
        }
        #expect(changedByDocument == 1)
        let clozeAfterOverride = try #require(try await repo.fetch(id: cloze.id))
        #expect(clozeAfterOverride.suspended == true)
        #expect(clozeAfterOverride.suspendedReason == .user)

        // Category off: the override still wins for the cloze card, and the passive card stays .mastery.
        try await setCategory(db, id: lectures, frequency: .off)
        let changedByCategory = try await db.writer.write { db in
            try ReviewSuspension.recompute(categoryId: lectures, db)
        }
        #expect(changedByCategory == 0)
        #expect(try await repo.fetch(id: cloze.id)?.suspendedReason == .user)
        #expect(try await repo.fetch(id: passive.id)?.suspendedReason == .mastery)

        // A document in another category is untouched by a recompute of this category.
        let otherHighlight = try await seedHighlight(db, categoryId: BuiltinCategory.notes.id)
        let otherCard = try ReviewCardFactory.passive(highlightId: otherHighlight.id, now: now)
        try await db.writer.write { db in try otherCard.insert(db) }
        let changedOther = try await db.writer.write { db in
            try ReviewSuspension.recompute(categoryId: lectures, db)
        }
        #expect(changedOther == 0)
        #expect(try await repo.fetch(id: otherCard.id)?.suspended == false)

        // Recomputing with nothing changed writes nothing.
        let unchanged = try await db.writer.write { db in
            try ReviewSuspension.recompute(highlightIds: [], db)
        }
        #expect(unchanged == 0)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }
}
