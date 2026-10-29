import Foundation
import GRDB
import Testing
@testable import StudyReader

/// SPEC F-19 AC2 and ADR-0021: a category's frequency change recomputes the suspension of its cards.
/// Runs against an in-memory database; the rule itself is tested in FrequencyPolicyTests.
extension FrequencyPolicyTests {
    private func seedHighlight(_ db: AppDatabase, documentId: String) async throws -> Highlight {
        let highlight = TestData.highlight(documentId: documentId)
        try await HighlightRepository(database: db).insert(highlight)
        return highlight
    }

    /// Inserts one card. Suspension is left for `ReviewSuspension.recompute`, as the rule requires.
    private func seedCard(
        _ db: AppDatabase,
        highlightId: String,
        cardType: CardType = .passive,
        override: ReviewFrequency? = nil
    ) async throws -> ReviewCard {
        var card: ReviewCard
        if cardType == .passive {
            card = try ReviewCardFactory.passive(highlightId: highlightId, now: TestData.referenceDate)
        } else {
            card = try ReviewCardFactory.mastery(
                highlightId: highlightId, cardType: cardType, clozeRanges: [[0, 4]],
                question: nil, answer: "Sample", now: TestData.referenceDate
            )
        }
        card.frequencyOverride = override
        let inserted = card
        try await db.writer.write { db in try inserted.insert(db) }
        return inserted
    }

    /// The stored reason (nil = active). Also checks that `suspended` agrees with it.
    private func suspendedReason(_ db: AppDatabase, _ cardId: String) async throws -> SuspendedReason? {
        let card = try #require(try await ReviewCardRepository(database: db).fetch(id: cardId))
        #expect(card.suspended == (card.suspendedReason != nil))
        return card.suspendedReason
    }

    @Test func offSuspends() async throws {
        let db = try AppDatabase.makeInMemory()
        let paper = BuiltinCategory.paper.id
        let document = TestData.document(categoryId: paper)
        try await DocumentRepository(database: db).insert(document)

        let highlightA = try await seedHighlight(db, documentId: document.id)
        let highlightB = try await seedHighlight(db, documentId: document.id)
        let highlightC = try await seedHighlight(db, documentId: document.id)
        let highlightD = try await seedHighlight(db, documentId: document.id)
        let cardA = try await seedCard(db, highlightId: highlightA.id)
        let cardB = try await seedCard(db, highlightId: highlightB.id, override: .high)
        let cardC = try await seedCard(db, highlightId: highlightC.id, override: .off)
        let cardD = try await seedCard(db, highlightId: highlightD.id)
        let clozeD = try await seedCard(db, highlightId: highlightD.id, cardType: .cloze)
        try await db.writer.write { db in
            _ = try ReviewSuspension.recompute(documentIds: [document.id], db)
        }

        // Starting state: only C (override off) and D's passive card (mastery) are suspended.
        #expect(try await suspendedReason(db, cardA.id) == nil)
        #expect(try await suspendedReason(db, cardB.id) == nil)
        #expect(try await suspendedReason(db, cardC.id) == .user)
        #expect(try await suspendedReason(db, cardD.id) == .mastery)
        #expect(try await suspendedReason(db, clozeD.id) == nil)

        let changedOff = try await CategoryRepository(database: db).setFrequency(id: paper, .off)
        #expect(changedOff == 2)
        #expect(try await suspendedReason(db, cardA.id) == .frequencyOff)
        #expect(try await suspendedReason(db, cardB.id) == nil)
        #expect(try await suspendedReason(db, cardC.id) == .user)
        #expect(try await suspendedReason(db, cardD.id) == .mastery)
        #expect(try await suspendedReason(db, clozeD.id) == .frequencyOff)

        let changedOn = try await CategoryRepository(database: db).setFrequency(id: paper, .normal)
        #expect(changedOn == 2)
        #expect(try await suspendedReason(db, cardA.id) == nil)
        #expect(try await suspendedReason(db, cardB.id) == nil)
        #expect(try await suspendedReason(db, cardC.id) == .user)
        #expect(try await suspendedReason(db, cardD.id) == .mastery)
        #expect(try await suspendedReason(db, clozeD.id) == nil)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func offAppliesToBuiltinAndCustomCategories() async throws {
        let db = try AppDatabase.makeInMemory()
        let categories = CategoryRepository(database: db)
        let documents = DocumentRepository(database: db)
        let custom = try await categories.create(name: "Thesis reading")
        let lectureDoc = TestData.document(categoryId: BuiltinCategory.lectureSlides.id)
        let customDoc = TestData.document(categoryId: custom.id)
        let notesDoc = TestData.document(categoryId: BuiltinCategory.notes.id)
        for document in [lectureDoc, customDoc, notesDoc] {
            try await documents.insert(document)
        }

        // Each document: one normal passive card and one card overridden to off.
        let lectureA = try await seedCard(db, highlightId: try await seedHighlight(db, documentId: lectureDoc.id).id)
        _ = try await seedCard(db, highlightId: try await seedHighlight(db, documentId: lectureDoc.id).id, override: .off)
        let customA = try await seedCard(db, highlightId: try await seedHighlight(db, documentId: customDoc.id).id)
        _ = try await seedCard(db, highlightId: try await seedHighlight(db, documentId: customDoc.id).id, override: .off)
        let notesA = try await seedCard(db, highlightId: try await seedHighlight(db, documentId: notesDoc.id).id)
        try await db.writer.write { db in
            _ = try ReviewSuspension.recompute(documentIds: [lectureDoc.id, customDoc.id, notesDoc.id], db)
        }

        let lectureOff = try await categories.setFrequency(id: BuiltinCategory.lectureSlides.id, .off)
        #expect(lectureOff == 1)
        #expect(try await suspendedReason(db, lectureA.id) == .frequencyOff)
        #expect(try await suspendedReason(db, customA.id) == nil)
        #expect(try await suspendedReason(db, notesA.id) == nil)

        let customOff = try await categories.setFrequency(id: custom.id, .off)
        #expect(customOff == 1)
        #expect(try await suspendedReason(db, customA.id) == .frequencyOff)
        #expect(try await suspendedReason(db, lectureA.id) == .frequencyOff)
        #expect(try await suspendedReason(db, notesA.id) == nil)

        let lectureOn = try await categories.setFrequency(id: BuiltinCategory.lectureSlides.id, .normal)
        let customOn = try await categories.setFrequency(id: custom.id, .normal)
        #expect(lectureOn == 1)
        #expect(customOn == 1)
        #expect(try await suspendedReason(db, lectureA.id) == nil)
        #expect(try await suspendedReason(db, customA.id) == nil)
        #expect(try await suspendedReason(db, notesA.id) == nil)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }
}
