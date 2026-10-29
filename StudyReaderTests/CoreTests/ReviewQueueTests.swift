import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("ReviewQueue")
struct ReviewQueueTests {
    private let day: TimeInterval = 86_400
    private let r = TestData.referenceDate

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func seedDocument(_ db: AppDatabase, title: String = "Test Document") async throws -> LibraryDocument {
        let document = TestData.document(title: title)
        try await DocumentRepository(database: db).insert(document)
        return document
    }

    /// Inserts a highlight (created at `highlightCreatedAt`) and a card on it. Rows are written as given, so tests
    /// control `state`, `dueAt`, `introducedAt` and `suspended` directly.
    private func seedCard(
        _ db: AppDatabase,
        documentId: String,
        cardId: String = UUID().uuidString,
        state: ReviewCardState,
        dueAt: Date = TestData.referenceDate,
        introducedAt: Date? = nil,
        suspended: Bool = false,
        highlightCreatedAt: Date = TestData.referenceDate
    ) async throws -> ReviewCard {
        let highlight = TestData.highlight(documentId: documentId, createdAt: highlightCreatedAt)
        try await HighlightRepository(database: db).insert(highlight)
        var card = TestData.reviewCard(highlightId: highlight.id, id: cardId, dueAt: dueAt, state: state)
        card.introducedAt = introducedAt
        card.suspended = suspended
        card.suspendedReason = suspended ? .user : nil
        let inserted = card
        try await db.writer.write { db in try inserted.insert(db) }
        return card
    }

    private func insertLog(
        _ db: AppDatabase,
        cardId: String,
        at reviewedAt: Date,
        kind: ReviewSessionKind = .daily,
        themedReviewId: String? = nil
    ) async throws {
        let entry = ReviewLogEntry(
            id: UUID().uuidString,
            cardId: cardId,
            rating: ReviewRating.good.rawValue,
            reviewedAt: reviewedAt,
            sessionKind: kind,
            themedReviewId: themedReviewId,
            fsrsLog: "{}"
        )
        try await db.writer.write { db in try entry.insert(db) }
    }

    private func logs(_ db: AppDatabase, cardId: String) async throws -> [ReviewLogEntry] {
        try await db.writer.read { db in
            try ReviewLogEntry.filter(Column("cardId") == cardId).fetchAll(db)
        }
    }

    @Test func dailyQueueSplitsDueAndNew() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: db)
        let document = try await seedDocument(db)
        let dayStart = r.addingTimeInterval(-3600)

        let reviewOld = try await seedCard(db, documentId: document.id, state: .review, dueAt: r.addingTimeInterval(-2 * day))
        let reviewHour = try await seedCard(db, documentId: document.id, state: .review, dueAt: r.addingTimeInterval(-3600))
        _ = try await seedCard(db, documentId: document.id, state: .review, dueAt: r.addingTimeInterval(day))
        let relearning = try await seedCard(db, documentId: document.id, state: .relearning, dueAt: r.addingTimeInterval(-3 * day))
        let neverIntroduced = try await seedCard(db, documentId: document.id, state: .new, dueAt: r)
        _ = try await seedCard(db, documentId: document.id, state: .new, dueAt: r, introducedAt: r.addingTimeInterval(-600))
        _ = try await seedCard(db, documentId: document.id, state: .review, dueAt: r.addingTimeInterval(-5 * day), suspended: true)

        let snapshot = try await repo.dailyQueue(now: r, dayStart: dayStart)
        #expect(snapshot.due.map(\.cardId) == [relearning.id, reviewOld.id, reviewHour.id])
        #expect(snapshot.due.map(\.state) == [.relearning, .review, .review])
        #expect(snapshot.new.map(\.cardId) == [neverIntroduced.id])
        #expect(snapshot.new.first?.introducedAt == nil)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func newOrderedByHighlightCreation() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: db)
        let document = try await seedDocument(db)

        let newest = try await seedCard(
            db, documentId: document.id, cardId: "card-newest", state: .new,
            highlightCreatedAt: r.addingTimeInterval(-day)
        )
        let oldest = try await seedCard(
            db, documentId: document.id, cardId: "card-oldest", state: .new,
            highlightCreatedAt: r.addingTimeInterval(-3 * day)
        )
        // Same highlight creation time: ties fall back to cardId, so "card-a" comes before "card-b".
        let tieB = try await seedCard(
            db, documentId: document.id, cardId: "card-b", state: .new,
            highlightCreatedAt: r.addingTimeInterval(-2 * day)
        )
        let tieA = try await seedCard(
            db, documentId: document.id, cardId: "card-a", state: .new,
            highlightCreatedAt: r.addingTimeInterval(-2 * day)
        )

        let snapshot = try await repo.dailyQueue(now: r, dayStart: r.addingTimeInterval(-3600))
        #expect(snapshot.new.map(\.cardId) == [oldest.id, tieA.id, tieB.id, newest.id])
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func activityCountsToday() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: db)
        let document = try await seedDocument(db)
        let dayStart = r.addingTimeInterval(-3600)

        let yesterdayRated = try await seedCard(db, documentId: document.id, state: .review, dueAt: r.addingTimeInterval(-day))
        let dailyToday = try await seedCard(db, documentId: document.id, state: .review, dueAt: r.addingTimeInterval(-day))
        let themedToday = try await seedCard(db, documentId: document.id, state: .review, dueAt: r.addingTimeInterval(-day))
        let introduced = try await seedCard(
            db, documentId: document.id, state: .new, introducedAt: dayStart.addingTimeInterval(10)
        )
        let twice = try await seedCard(db, documentId: document.id, state: .review, dueAt: r.addingTimeInterval(-3600))

        try await insertLog(db, cardId: yesterdayRated.id, at: dayStart.addingTimeInterval(-1))
        try await insertLog(db, cardId: dailyToday.id, at: dayStart)
        try await insertLog(db, cardId: themedToday.id, at: r, kind: .themed)
        try await insertLog(db, cardId: twice.id, at: r.addingTimeInterval(-2 * day))
        try await insertLog(db, cardId: twice.id, at: r.addingTimeInterval(-day))

        let snapshot = try await repo.dailyQueue(now: r, dayStart: dayStart)
        let activity = snapshot.activity
        #expect(activity.ratedCardIds == [dailyToday.id, themedToday.id])
        #expect(activity.dailyRatedCardIds == [dailyToday.id])
        #expect(activity.themedRatedCardIds == [themedToday.id])
        #expect(activity.introducedCardIds == [introduced.id])

        let twiceEntry = snapshot.due.first { $0.cardId == twice.id }
        #expect(twiceEntry?.lastReviewedAt == r.addingTimeInterval(-day))
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func recordRatingWritesCardAndLog() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: db)
        let document = try await seedDocument(db)
        let card = try await seedCard(db, documentId: document.id, state: .new, dueAt: r)

        let first = RatingWrite(
            cardId: card.id,
            fsrsCard: "{\"reps\":1}",
            dueAt: r.addingTimeInterval(600),
            state: .learning,
            reviewedAt: r,
            rating: .good,
            sessionKind: .daily,
            themedReviewId: nil,
            fsrsLog: "{\"rating\":3}"
        )
        let entry = try await repo.recordRating(first)
        #expect(entry.rating == 3)

        let updated = try #require(try await repo.fetch(id: card.id))
        #expect(updated.fsrsCard == "{\"reps\":1}")
        #expect(updated.dueAt == r.addingTimeInterval(600))
        #expect(updated.state == .learning)
        #expect(updated.introducedAt == r)

        let stored = try await logs(db, cardId: card.id)
        #expect(stored.count == 1)
        let log = try #require(stored.first)
        #expect(log.id == entry.id)
        #expect(log.rating == 3)
        #expect(log.sessionKind == .daily)
        #expect(log.themedReviewId == nil)
        #expect(log.fsrsLog == "{\"rating\":3}")
        #expect(log.reviewedAt == r)

        let second = RatingWrite(
            cardId: card.id,
            fsrsCard: "{\"reps\":2}",
            dueAt: r.addingTimeInterval(3 * day),
            state: .review,
            reviewedAt: r.addingTimeInterval(700),
            rating: .easy,
            sessionKind: .daily,
            themedReviewId: nil,
            fsrsLog: "{\"rating\":4}"
        )
        try await repo.recordRating(second)
        let afterSecond = try #require(try await repo.fetch(id: card.id))
        #expect(afterSecond.introducedAt == r)
        #expect(afterSecond.state == .review)
        #expect(try await logs(db, cardId: card.id).count == 2)

        let unknownId = "99999999-0000-0000-0000-000000000000"
        let total = try await db.writer.read { db in try ReviewLogEntry.fetchCount(db) }
        await #expect(throws: RepositoryError.notFound) {
            try await repo.recordRating(RatingWrite(
                cardId: unknownId,
                fsrsCard: "{}",
                dueAt: r,
                state: .review,
                reviewedAt: r,
                rating: .good,
                sessionKind: .daily,
                themedReviewId: nil,
                fsrsLog: "{}"
            ))
        }
        #expect(try await db.writer.read { db in try ReviewLogEntry.fetchCount(db) } == total)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func themedRatingKeepsReviewId() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: db)
        let document = try await seedDocument(db)
        let card = try await seedCard(db, documentId: document.id, state: .review, dueAt: r)
        let theme = TestData.themedReview()
        try await db.writer.write { db in try theme.insert(db) }

        try await repo.recordRating(RatingWrite(
            cardId: card.id,
            fsrsCard: "{}",
            dueAt: r.addingTimeInterval(day),
            state: .review,
            reviewedAt: r,
            rating: .hard,
            sessionKind: .themed,
            themedReviewId: theme.id,
            fsrsLog: "{}"
        ))
        let stored = try #require(try await logs(db, cardId: card.id).first)
        #expect(stored.sessionKind == .themed)
        #expect(stored.themedReviewId == theme.id)

        // Deleting the themed review keeps the log and clears the reference (ON DELETE SET NULL).
        try await db.writer.write { db in _ = try ThemedReview.deleteOne(db, key: theme.id) }
        let afterDelete = try #require(try await logs(db, cardId: card.id).first)
        #expect(afterDelete.themedReviewId == nil)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func itemsKeepOrderAndCarryDisplayData() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: db)
        let biology = try await seedDocument(db, title: "Biology")
        let chemistry = try await seedDocument(db, title: "Chemistry")
        try await db.writer.write { db in
            var category = try #require(try DocumentCategory.fetchOne(db, key: BuiltinCategory.lectureSlides.id))
            category.frequency = .high
            try category.update(db, columns: ["frequency"])
        }
        let cardA = try await seedCard(db, documentId: biology.id, cardId: "card-a", state: .review)
        let cardB = try await seedCard(db, documentId: chemistry.id, cardId: "card-b", state: .review)

        let alpha = TestData.tag(name: "beta")
        let beta = TestData.tag(name: "Alpha")
        try await db.writer.write { db in
            try alpha.insert(db)
            try beta.insert(db)
            try HighlightTag(highlightId: cardB.highlightId, tagId: alpha.id).insert(db)
            try HighlightTag(highlightId: cardB.highlightId, tagId: beta.id).insert(db)
        }

        let items = try await repo.items(cardIds: [cardB.id, "missing", cardA.id])
        #expect(items.map(\.card.id) == [cardB.id, cardA.id])

        let itemB = try #require(items.first)
        #expect(itemB.highlight.id == cardB.highlightId)
        #expect(itemB.documentTitle == "Chemistry")
        #expect(itemB.categoryFrequency == .high)
        #expect(itemB.tagNames == ["Alpha", "beta"])

        let itemA = try #require(items.last)
        #expect(itemA.documentTitle == "Biology")
        #expect(itemA.tagNames.isEmpty)

        #expect(try await repo.item(cardId: "missing") == nil)
        #expect(try await repo.item(cardId: cardA.id)?.documentTitle == "Biology")
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func observeDailyQueueReactsToRatings() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: db)
        let document = try await seedDocument(db)
        let card = try await seedCard(db, documentId: document.id, state: .review, dueAt: r.addingTimeInterval(-3600))
        let now = FixedNow(r)
        var iterator = repo.observeDailyQueue(now: now, calendar: utc).makeAsyncIterator()

        let first = try #require(try await iterator.next())
        #expect(first.due.map(\.cardId) == [card.id])

        try await repo.recordRating(RatingWrite(
            cardId: card.id,
            fsrsCard: "{}",
            dueAt: r.addingTimeInterval(3 * day),
            state: .review,
            reviewedAt: r,
            rating: .good,
            sessionKind: .daily,
            themedReviewId: nil,
            fsrsLog: "{}"
        ))
        let next = try #require(try await iterator.next())
        #expect(next.due.isEmpty)
        #expect(next.activity.ratedCardIds == [card.id])
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func dueCountBefore() async throws {
        let db = try AppDatabase.makeInMemory()
        let repo = ReviewCardRepository(database: db)
        let document = try await seedDocument(db)
        _ = try await seedCard(db, documentId: document.id, state: .review, dueAt: r.addingTimeInterval(-day))
        _ = try await seedCard(db, documentId: document.id, state: .review, dueAt: r.addingTimeInterval(day))
        _ = try await seedCard(db, documentId: document.id, state: .new, dueAt: r.addingTimeInterval(-day))
        _ = try await seedCard(
            db, documentId: document.id, state: .review, dueAt: r.addingTimeInterval(-day), suspended: true
        )

        #expect(try await repo.dueCount(before: r) == 1)
        #expect(try await repo.dueCount(before: r.addingTimeInterval(2 * day)) == 2)
        #expect(try await repo.dueCount(before: r.addingTimeInterval(-2 * day)) == 0)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }
}
