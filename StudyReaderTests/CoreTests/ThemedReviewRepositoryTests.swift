import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("ThemedReviewRepository")
struct ThemedReviewRepositoryTests {
    private let r = TestData.referenceDate
    private let day: TimeInterval = 86_400

    private func makeRepo() throws -> (AppDatabase, ThemedReviewRepository) {
        let db = try AppDatabase.makeInMemory()
        return (db, ThemedReviewRepository(database: db))
    }

    private func seedDocument(
        _ db: AppDatabase,
        id: String = UUID().uuidString,
        title: String = "Test Document",
        categoryId: String = BuiltinCategory.lectureSlides.id
    ) async throws -> String {
        try await DocumentRepository(database: db).insert(
            TestData.document(id: id, title: title, categoryId: categoryId)
        )
        return id
    }

    /// Inserts a highlight (with tags, which must already exist) and a card on it, with the given state.
    @discardableResult
    private func seedCard(
        _ db: AppDatabase,
        cardId: String = UUID().uuidString,
        documentId: String,
        color: HighlightColor = .yellow,
        tagIds: [String] = [],
        state: ReviewCardState = .review,
        dueAt: Date = TestData.referenceDate,
        suspended: Bool = false,
        createdAt: Date = TestData.referenceDate
    ) async throws -> String {
        let highlight = TestData.highlight(documentId: documentId, color: color, createdAt: createdAt)
        try await HighlightRepository(database: db).insert(highlight, tagIds: tagIds)
        var card = TestData.reviewCard(highlightId: highlight.id, id: cardId, dueAt: dueAt, state: state)
        card.suspended = suspended
        card.suspendedReason = suspended ? .user : nil
        let inserted = card
        try await db.writer.write { db in try inserted.insert(db) }
        return cardId
    }

    private func insertLog(
        _ db: AppDatabase,
        cardId: String,
        at reviewedAt: Date,
        kind: ReviewSessionKind = .daily,
        themedReviewId: String? = nil
    ) async throws -> String {
        let entry = ReviewLogEntry(
            id: UUID().uuidString,
            cardId: cardId,
            rating: ReviewRating.good.rawValue,
            reviewedAt: reviewedAt,
            sessionKind: kind,
            themedReviewId: themedReviewId,
            fsrsLog: "{}"
        )
        let inserted = entry
        try await db.writer.write { db in try inserted.insert(db) }
        return entry.id
    }

    @Test func createValidatesAndStores() async throws {
        let (db, repo) = try makeRepo()
        let filter = ThemedReviewFilter(tagIds: ["tag-1"], tagMode: .all, colors: [.yellow])
        let valid = ThemedReviewDraft(
            name: "  Exam week  ",
            filter: filter,
            cardsPerSession: 10,
            interval: .weekdays([6, 2, 2]),
            orderMode: .random
        )
        let created = try await repo.create(valid, at: r)
        let stored = try await repo.fetch(id: created.id)
        #expect(stored?.name == "Exam week")
        #expect(stored?.filter == filter)
        #expect(stored?.cardsPerSession == 10)
        #expect(stored?.interval == .weekdays([2, 6]))
        #expect(stored?.orderMode == .random)
        #expect(stored?.lastCompletedAt == nil)
        #expect(stored?.createdAt == r)

        // A name of exactly 80 characters is accepted.
        _ = try await repo.create(ThemedReviewDraft(name: String(repeating: "a", count: 80)), at: r)

        let invalid: [(ThemedReviewDraft, ThemedReviewError)] = [
            (ThemedReviewDraft(name: ""), .emptyName),
            (ThemedReviewDraft(name: " \n "), .emptyName),
            (ThemedReviewDraft(name: String(repeating: "a", count: 81)), .nameTooLong),
            (ThemedReviewDraft(name: "x", cardsPerSession: 4), .invalidCardsPerSession),
            (ThemedReviewDraft(name: "x", cardsPerSession: 101), .invalidCardsPerSession),
            (ThemedReviewDraft(name: "x", interval: .everyNDays(0)), .invalidInterval),
            (ThemedReviewDraft(name: "x", interval: .everyNDays(366)), .invalidInterval),
            (ThemedReviewDraft(name: "x", interval: .weekdays([])), .invalidInterval),
            (ThemedReviewDraft(name: "x", interval: .weekdays([8])), .invalidInterval),
        ]
        for (draft, expected) in invalid {
            await #expect(throws: expected) {
                _ = try await repo.create(draft, at: r)
            }
        }
        // Only the valid review and the 80-character one exist.
        #expect(try await repo.fetchAll().count == 2)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func updateKeepsCompletion() async throws {
        let (_, repo) = try makeRepo()
        let created = try await repo.create(ThemedReviewDraft(name: "Exam"), at: r)
        try await repo.markCompleted(id: created.id, at: r.addingTimeInterval(day))

        try await repo.update(
            id: created.id,
            ThemedReviewDraft(name: "Renamed", cardsPerSession: 30, interval: .everyNDays(3), orderMode: .random)
        )
        let stored = try await repo.fetch(id: created.id)
        #expect(stored?.name == "Renamed")
        #expect(stored?.cardsPerSession == 30)
        #expect(stored?.interval == .everyNDays(3))
        #expect(stored?.orderMode == .random)
        #expect(stored?.lastCompletedAt == r.addingTimeInterval(day))

        await #expect(throws: ThemedReviewError.notFound) {
            try await repo.update(id: "missing", ThemedReviewDraft(name: "x"))
        }
        await #expect(throws: ThemedReviewError.notFound) {
            try await repo.markCompleted(id: "missing", at: r)
        }
    }

    @Test func duplicateAndDelete() async throws {
        let (db, repo) = try makeRepo()
        let original = try await repo.create(ThemedReviewDraft(name: "Exam week", cardsPerSession: 12), at: r)
        try await repo.markCompleted(id: original.id, at: r)

        let copy = try await repo.duplicate(id: original.id, at: r.addingTimeInterval(2 * day))
        #expect(copy.name == "Exam week copy")
        #expect(copy.id != original.id)
        #expect(copy.cardsPerSession == 12)
        #expect(copy.createdAt == r.addingTimeInterval(2 * day))
        #expect(copy.lastCompletedAt == nil)

        let documentId = try await seedDocument(db)
        let cardId = try await seedCard(db, documentId: documentId)
        let logId = try await insertLog(db, cardId: cardId, at: r, kind: .themed, themedReviewId: original.id)

        #expect(try await repo.delete(id: original.id) == true)
        #expect(try await repo.delete(id: original.id) == false)
        #expect(try await repo.fetch(id: original.id) == nil)
        #expect(try await repo.fetch(id: copy.id) != nil)

        let log = try await db.writer.read { db in try ReviewLogEntry.fetchOne(db, key: logId) }
        #expect(log != nil)
        #expect(log?.themedReviewId == nil)
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test(.timeLimit(.minutes(1)))
    func observeAllOrdersByName() async throws {
        let (_, repo) = try makeRepo()
        var iterator = repo.observeAll().makeAsyncIterator()
        #expect(try await iterator.next()?.isEmpty == true)

        for name in ["b", "A", "c"] {
            _ = try await repo.create(ThemedReviewDraft(name: name), at: r)
        }
        var names: [String] = []
        while names.count < 3 {
            guard let next = try await iterator.next() else { break }
            names = next.map(\.name)
        }
        #expect(names == ["A", "b", "c"])
        #expect(try await repo.fetchAll().map(\.name) == ["A", "b", "c"])
    }

    @Test(.timeLimit(.minutes(1)))
    func themedQueueMatchesTheFilter() async throws {
        let (db, repo) = try makeRepo()
        let docA = try await seedDocument(db, id: "doc-a", title: "Alpha", categoryId: BuiltinCategory.lectureSlides.id)
        let docB = try await seedDocument(db, id: "doc-b", title: "Beta", categoryId: BuiltinCategory.paper.id)
        let exam = TestData.tag(name: "exam", id: "tag-exam")
        let ml = TestData.tag(name: "ML", id: "tag-ml")
        try await db.writer.write { db in
            try exam.insert(db)
            try ml.insert(db)
        }

        // c1: docA, yellow, exam+ml, due later. c2: docA, green, ml, new. c3: docB, yellow, exam, overdue.
        // c4: docB, blue, no tags, suspended. c5: docA, yellow, no tags, new.
        try await seedCard(db, cardId: "c1", documentId: docA, color: .yellow, tagIds: [exam.id, ml.id],
                           state: .review, dueAt: r.addingTimeInterval(day))
        try await seedCard(db, cardId: "c2", documentId: docA, color: .green, tagIds: [ml.id], state: .new)
        try await seedCard(db, cardId: "c3", documentId: docB, color: .yellow, tagIds: [exam.id],
                           state: .review, dueAt: r.addingTimeInterval(-day))
        try await seedCard(db, cardId: "c4", documentId: docB, color: .blue, state: .review, suspended: true)
        try await seedCard(db, cardId: "c5", documentId: docA, color: .yellow, state: .new)

        let cases: [(name: String, filter: ThemedReviewFilter, expected: [String])] = [
            ("empty filter", ThemedReviewFilter(), ["c1", "c2", "c3", "c5"]),
            ("tag any exam", ThemedReviewFilter(tagIds: [exam.id], tagMode: .any), ["c1", "c3"]),
            ("tags all exam+ml", ThemedReviewFilter(tagIds: [exam.id, ml.id], tagMode: .all), ["c1"]),
            ("tags any exam+ml", ThemedReviewFilter(tagIds: [exam.id, ml.id], tagMode: .any), ["c1", "c2", "c3"]),
            ("document", ThemedReviewFilter(documentIds: [docB]), ["c3"]),
            ("category paper", ThemedReviewFilter(categoryIds: [BuiltinCategory.paper.id]), ["c3"]),
            ("colour yellow", ThemedReviewFilter(colors: [.yellow]), ["c1", "c3", "c5"]),
            ("unknown tag", ThemedReviewFilter(tagIds: ["tag-missing"]), []),
        ]
        for testCase in cases {
            let snapshot = try await repo.themedQueue(filter: testCase.filter, dayStart: r)
            #expect(snapshot.candidates.map(\.cardId) == testCase.expected, "\(testCase.name)")
        }

        // New and future cards are included with their state and due date.
        let all = try await repo.themedQueue(filter: ThemedReviewFilter(), dayStart: r)
        #expect(all.candidates.first { $0.cardId == "c2" }?.state == .new)
        #expect(all.candidates.first { $0.cardId == "c1" }?.dueAt == r.addingTimeInterval(day))
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }

    @Test func ratedTodayIsReported() async throws {
        let (db, repo) = try makeRepo()
        let documentId = try await seedDocument(db)
        let dayStart = r
        try await seedCard(db, cardId: "c-before", documentId: documentId)
        try await seedCard(db, cardId: "c-boundary", documentId: documentId)
        try await seedCard(db, cardId: "c-today", documentId: documentId)
        try await seedCard(db, cardId: "c-unrated", documentId: documentId)

        _ = try await insertLog(db, cardId: "c-before", at: dayStart.addingTimeInterval(-60))
        _ = try await insertLog(db, cardId: "c-boundary", at: dayStart)
        _ = try await insertLog(db, cardId: "c-today", at: dayStart.addingTimeInterval(60), kind: .themed)

        let snapshot = try await repo.themedQueue(filter: ThemedReviewFilter(), dayStart: dayStart)
        #expect(snapshot.ratedTodayCardIds == ["c-boundary", "c-today"])
        // Rated cards stay candidates; only the session excludes them.
        #expect(snapshot.candidates.map(\.cardId) == ["c-before", "c-boundary", "c-today", "c-unrated"])
        try await db.writer.write { db in try FTSIntegrity.check(db) }
    }
}
