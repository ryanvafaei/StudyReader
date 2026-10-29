import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("FlashcardQuery")
struct FlashcardQueryTests {
    private let day: TimeInterval = 86_400
    private let r = TestData.referenceDate

    private func seedDocument(
        _ db: AppDatabase,
        categoryId: String = BuiltinCategory.lectureSlides.id
    ) async throws -> LibraryDocument {
        let document = TestData.document(categoryId: categoryId)
        try await DocumentRepository(database: db).insert(document)
        return document
    }

    /// Inserts a highlight (with `tagIds`) and one card on it. Rows are written as given, so tests control `state`,
    /// `dueAt`, `suspended` and the card type directly.
    @discardableResult
    private func seedCard(
        _ db: AppDatabase,
        documentId: String,
        cardId: String = UUID().uuidString,
        cardType: CardType = .passive,
        state: ReviewCardState,
        dueAt: Date = TestData.referenceDate,
        suspended: Bool = false,
        tagIds: [String] = []
    ) async throws -> ReviewCard {
        let highlight = TestData.highlight(documentId: documentId)
        try await HighlightRepository(database: db).insert(highlight, tagIds: tagIds)
        var card = TestData.reviewCard(
            highlightId: highlight.id,
            id: cardId,
            cardType: cardType,
            dueAt: dueAt,
            state: state
        )
        card.suspended = suspended
        card.suspendedReason = suspended ? .user : nil
        let inserted = card
        try await db.writer.write { db in try inserted.insert(db) }
        return card
    }

    private func insertLog(_ db: AppDatabase, cardId: String, at reviewedAt: Date) async throws {
        let entry = ReviewLogEntry(
            id: UUID().uuidString,
            cardId: cardId,
            rating: ReviewRating.good.rawValue,
            reviewedAt: reviewedAt,
            sessionKind: .daily,
            themedReviewId: nil,
            fsrsLog: "{}"
        )
        try await db.writer.write { db in try entry.insert(db) }
    }

    private func ids(_ repo: ReviewCardRepository, _ filter: FlashcardFilter) async throws -> Set<String> {
        let items = try await repo.flashcards(filter: filter)
        return Set(items.map(\.id))
    }

    @Test func statesMapAsSpecified() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: db)
        let document = try await seedDocument(db)

        let newCard = try await seedCard(db, documentId: document.id, state: .new)
        let learning = try await seedCard(db, documentId: document.id, state: .learning, dueAt: r.addingTimeInterval(-day))
        let relearning = try await seedCard(db, documentId: document.id, state: .relearning, dueAt: r.addingTimeInterval(-2 * day))
        let review = try await seedCard(db, documentId: document.id, state: .review, dueAt: r.addingTimeInterval(day))
        let suspendedReview = try await seedCard(db, documentId: document.id, state: .review, suspended: true)
        let suspendedNew = try await seedCard(db, documentId: document.id, state: .new, suspended: true)

        let all = try await repo.flashcards(filter: FlashcardFilter())
        let stateById = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.state) })
        #expect(stateById == [
            newCard.id: .new,
            learning.id: .learning,
            relearning.id: .learning,
            review.id: .review,
            suspendedReview.id: .suspended,
            suspendedNew.id: .suspended,
        ])

        #expect(try await ids(repo, FlashcardFilter(states: [.learning])) == [learning.id, relearning.id])
        #expect(try await ids(repo, FlashcardFilter(states: [.new, .suspended]))
            == [newCard.id, suspendedReview.id, suspendedNew.id])
        #expect(try await ids(repo, FlashcardFilter(states: [.review])) == [review.id])
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func highlightFiltersCombine() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: db)
        let docA = try await seedDocument(db)
        let docB = try await seedDocument(db, categoryId: BuiltinCategory.paper.id)
        let tags = TagRepository(database: db)
        let alpha = try await tags.findOrCreate(name: "alpha", at: r).id
        let beta = try await tags.findOrCreate(name: "beta", at: r).id

        let c1 = try await seedCard(db, documentId: docA.id, state: .review, tagIds: [alpha])
        let c2 = try await seedCard(db, documentId: docA.id, state: .review, tagIds: [alpha, beta])
        let c3 = try await seedCard(db, documentId: docB.id, state: .review, tagIds: [beta])

        #expect(try await ids(repo, FlashcardFilter(documentIds: [docA.id])) == [c1.id, c2.id])
        #expect(try await ids(repo, FlashcardFilter(tagIds: [alpha])) == [c1.id, c2.id])
        #expect(try await ids(repo, FlashcardFilter(tagIds: [alpha, beta], tagMode: .all)) == [c2.id])
        #expect(try await ids(repo, FlashcardFilter(tagIds: [beta])) == [c2.id, c3.id])
        #expect(try await ids(repo, FlashcardFilter(categoryIds: [BuiltinCategory.paper.id])) == [c3.id])
        #expect(try await ids(repo, FlashcardFilter(documentIds: [docA.id], tagIds: [beta])) == [c2.id])
        #expect(try await ids(repo, FlashcardFilter(documentIds: [docA.id], categoryIds: [BuiltinCategory.paper.id])) == [])
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func dueRangeAndTypes() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: db)
        let document = try await seedDocument(db)

        let passive = try await seedCard(db, documentId: document.id, state: .review, dueAt: r.addingTimeInterval(-day))
        let cloze = try await seedCard(db, documentId: document.id, cardType: .cloze, state: .review, dueAt: r)
        let qa = try await seedCard(db, documentId: document.id, cardType: .qa, state: .review, dueAt: r.addingTimeInterval(day))
        let laterCloze = try await seedCard(db, documentId: document.id, cardType: .cloze, state: .review, dueAt: r.addingTimeInterval(2 * day))

        // dueFrom is inclusive, dueBefore exclusive.
        let masteryInWindow = FlashcardFilter(
            cardTypes: [.cloze, .qa],
            dueFrom: r,
            dueBefore: r.addingTimeInterval(2 * day)
        )
        #expect(try await ids(repo, masteryInWindow) == [cloze.id, qa.id])
        #expect(try await ids(repo, FlashcardFilter(cardTypes: [.passive])) == [passive.id])
        #expect(try await ids(repo, FlashcardFilter(dueFrom: r.addingTimeInterval(day))) == [qa.id, laterCloze.id])
        #expect(try await ids(repo, FlashcardFilter(dueBefore: r)) == [passive.id])
        #expect(try await ids(repo, FlashcardFilter()).count == 4)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func orderAndLastReview() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: db)
        let document = try await seedDocument(db)

        // Equal dueAt falls back to card id: "card-m" before "card-z".
        let later = try await seedCard(db, documentId: document.id, cardId: "card-x", state: .review, dueAt: r.addingTimeInterval(day))
        let z = try await seedCard(db, documentId: document.id, cardId: "card-z", state: .review, dueAt: r)
        let m = try await seedCard(db, documentId: document.id, cardId: "card-m", state: .review, dueAt: r)

        try await insertLog(db, cardId: z.id, at: r.addingTimeInterval(-3600))
        try await insertLog(db, cardId: z.id, at: r.addingTimeInterval(-100))

        let all = try await repo.flashcards(filter: FlashcardFilter())
        #expect(all.map(\.id) == [m.id, z.id, later.id])
        #expect(all[0].lastReviewedAt == nil)
        #expect(all[1].lastReviewedAt == r.addingTimeInterval(-100))
        #expect(all[2].lastReviewedAt == nil)
        #expect(all[1].item.card.id == z.id)
        #expect(all[1].item.documentTitle == document.title)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func observeEmitsOnChange() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: db)
        let document = try await seedDocument(db)
        let card = try await seedCard(db, documentId: document.id, state: .review)

        let observation = repo.observeFlashcards(filter: FlashcardFilter())
        let recorder = FlashcardRecorder()
        let task = Task {
            for try await items in observation {
                await recorder.record(items)
            }
        }
        defer { task.cancel() }

        let emitted = await TestWait.until { await recorder.state(of: card.id) == .review }
        #expect(emitted)

        try await repo.updateFrequencyOverride(cardId: card.id, override: .off, rescheduled: nil)

        let suspended = await TestWait.until { await recorder.state(of: card.id) == .suspended }
        #expect(suspended)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }
}

/// Collects the latest observed Flashcards list for the observe test.
private actor FlashcardRecorder {
    private var latest: [FlashcardItem] = []

    func record(_ items: [FlashcardItem]) {
        latest = items
    }

    func state(of cardId: String) -> FlashcardState? {
        latest.first { $0.id == cardId }?.state
    }
}
