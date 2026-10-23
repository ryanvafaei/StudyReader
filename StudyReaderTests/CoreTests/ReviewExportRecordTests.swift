import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite("Review and export record round trips")
struct ReviewExportRecordTests {
    private static let documentId = "40000000-0000-0000-0000-0000000000d1"
    private static let highlightId = "40000000-0000-0000-0000-0000000000e1"

    /// Inserts a document and a highlight so review cards and embeddings have a parent.
    private static func insertHighlight(_ db: AppDatabase, id: String = highlightId) async throws -> Highlight {
        let document = TestData.document(id: documentId)
        let highlight = TestData.highlight(documentId: documentId, id: id)
        try await db.writer.write { db in
            try document.insert(db)
            try highlight.insert(db)
        }
        return highlight
    }

    @Test func reviewCardRoundTrip() async throws {
        let db = try AppDatabase.makeInMemory()
        let highlight = try await Self.insertHighlight(db)

        let passive = TestData.reviewCard(
            highlightId: highlight.id, id: "50000000-0000-0000-0000-000000000001")
        let cloze = ReviewCard(
            id: "50000000-0000-0000-0000-000000000002",
            highlightId: highlight.id,
            cardType: .cloze,
            clozeRanges: [[0, 4], [10, 3]],
            fsrsCard: "{}",
            dueAt: TestData.referenceDate,
            state: .review,
            frequencyOverride: .high,
            suspended: true,
            suspendedReason: .mastery,
            introducedAt: TestData.referenceDate,
            createdAt: TestData.referenceDate
        )
        let qa = ReviewCard(
            id: "50000000-0000-0000-0000-000000000003",
            highlightId: highlight.id,
            cardType: .qa,
            question: "What is FSRS?",
            answer: "A spaced repetition scheduler.",
            fsrsCard: "{}",
            dueAt: TestData.referenceDate,
            state: .learning,
            createdAt: TestData.referenceDate
        )

        try await db.writer.write { db in
            try passive.insert(db)
            try cloze.insert(db)
            try qa.insert(db)
        }

        let fetched = try await db.reader.read { db in
            try (
                passive: ReviewCard.fetchOne(db, key: passive.id),
                cloze: ReviewCard.fetchOne(db, key: cloze.id),
                qa: ReviewCard.fetchOne(db, key: qa.id)
            )
        }
        #expect(fetched.passive == passive)
        #expect(fetched.cloze == cloze)
        #expect(fetched.qa == qa)
    }

    @Test func reviewLogRoundTripAndSetNull() async throws {
        let db = try AppDatabase.makeInMemory()
        let highlight = try await Self.insertHighlight(db)
        let card = TestData.reviewCard(highlightId: highlight.id, id: "51000000-0000-0000-0000-000000000001")
        let theme = TestData.themedReview(id: "52000000-0000-0000-0000-000000000001")
        let plain = ReviewLogEntry(
            id: "53000000-0000-0000-0000-000000000001",
            cardId: card.id,
            rating: 3,
            reviewedAt: TestData.referenceDate,
            sessionKind: .daily,
            fsrsLog: "{}"
        )
        let themed = ReviewLogEntry(
            id: "53000000-0000-0000-0000-000000000002",
            cardId: card.id,
            rating: 4,
            reviewedAt: TestData.referenceDate,
            sessionKind: .themed,
            themedReviewId: theme.id,
            fsrsLog: "{}"
        )

        try await db.writer.write { db in
            try card.insert(db)
            try theme.insert(db)
            try plain.insert(db)
            try themed.insert(db)
        }

        let before = try await db.reader.read { db in
            try (
                plain: ReviewLogEntry.fetchOne(db, key: plain.id),
                themed: ReviewLogEntry.fetchOne(db, key: themed.id)
            )
        }
        #expect(before.plain == plain)
        #expect(before.themed == themed)

        try await db.writer.write { db in
            _ = try ThemedReview.deleteOne(db, key: theme.id)
        }

        let after = try await db.reader.read { db in
            try (
                themedId: String.fetchOne(
                    db, sql: "SELECT themedReviewId FROM reviewLog WHERE id = ?", arguments: [themed.id]),
                logCount: Int.fetchOne(db, sql: "SELECT COUNT(*) FROM reviewLog") ?? 0
            )
        }
        #expect(after.themedId == nil)
        #expect(after.logCount == 2)
    }

    @Test func themedReviewRoundTrip() async throws {
        let db = try AppDatabase.makeInMemory()
        let review = ThemedReview(
            id: "54000000-0000-0000-0000-000000000001",
            name: "Exam week",
            filter: ThemedReviewFilter(
                tagIds: ["tag-a", "tag-b"],
                tagMode: .all,
                colors: [.blue, .pink]
            ),
            cardsPerSession: 35,
            interval: .weekdays([2, 4]),
            orderMode: .random,
            lastCompletedAt: TestData.referenceDate,
            createdAt: TestData.referenceDate
        )

        try await db.writer.write { db in
            try review.insert(db)
        }

        let fetched = try await db.reader.read { db in
            try (
                review: ThemedReview.fetchOne(db, key: review.id),
                filterType: String.fetchOne(db, sql: "SELECT typeof(filter) FROM themedReview WHERE id = ?", arguments: [review.id])
            )
        }
        #expect(fetched.review == review)
        #expect(fetched.filterType == "text")
    }

    @Test func exportTargetRoundTrip() async throws {
        let db = try AppDatabase.makeInMemory()
        let custom = ExportTarget(
            id: "55000000-0000-0000-0000-000000000001",
            title: "Biology tag",
            scope: .tag("t1"),
            options: ExportOptions(
                includeNotes: false,
                includeDocumentNotes: false,
                includeImages: false,
                groupBy: .tag
            ),
            googleFileId: "google-file-1",
            googleFolderId: "google-folder-1",
            format: .html,
            keepInSync: true,
            lastExportedAt: TestData.referenceDate,
            lastStatus: "ok",
            lastError: nil,
            createdAt: TestData.referenceDate
        )
        let defaults = TestData.exportTarget(id: "55000000-0000-0000-0000-000000000002")

        try await db.writer.write { db in
            try custom.insert(db)
            try defaults.insert(db)
        }

        let fetched = try await db.reader.read { db in
            try (
                custom: ExportTarget.fetchOne(db, key: custom.id),
                defaults: ExportTarget.fetchOne(db, key: defaults.id),
                defaultStatus: String.fetchOne(db, sql: "SELECT lastStatus FROM exportTarget WHERE id = ?", arguments: [defaults.id]),
                defaultFormat: String.fetchOne(db, sql: "SELECT format FROM exportTarget WHERE id = ?", arguments: [defaults.id]),
                defaultKeepInSync: Int.fetchOne(db, sql: "SELECT keepInSync FROM exportTarget WHERE id = ?", arguments: [defaults.id])
            )
        }
        #expect(fetched.custom == custom)
        #expect(fetched.defaults == defaults)
        #expect(fetched.defaultStatus == "never")
        #expect(fetched.defaultFormat == "markdown")
        #expect(fetched.defaultKeepInSync == 0)
    }

    @Test func embeddingRoundTrip() async throws {
        let db = try AppDatabase.makeInMemory()
        let highlight = try await Self.insertHighlight(db)
        let vector = ([1, 2, 3] as [Float]).withUnsafeBytes { Data($0) }
        let embedding = HighlightEmbedding(
            highlightId: highlight.id,
            modelId: "NLEmbedding.sentence.en",
            dimension: 3,
            vector: vector,
            sourceHash: "abc123"
        )

        try await db.writer.write { db in
            try embedding.insert(db)
        }

        let fetched = try await db.reader.read { db in
            try (
                embedding: HighlightEmbedding.fetchOne(db, key: highlight.id),
                vectorType: String.fetchOne(db, sql: "SELECT typeof(vector) FROM highlightEmbedding WHERE highlightId = ?", arguments: [highlight.id])
            )
        }
        #expect(fetched.embedding == embedding)
        #expect(fetched.embedding?.vector == vector)
        #expect(fetched.vectorType == "blob")
    }

    @Test func reviewCardColumnTypes() async throws {
        let db = try AppDatabase.makeInMemory()
        let highlight = try await Self.insertHighlight(db)
        let card = TestData.reviewCard(highlightId: highlight.id, id: "56000000-0000-0000-0000-000000000001")

        try await db.writer.write { db in
            try card.insert(db)
        }

        let stored = try await db.reader.read { db in
            try (
                dueType: String.fetchOne(db, sql: "SELECT typeof(dueAt) FROM reviewCard WHERE id = ?", arguments: [card.id]),
                dueValue: Double.fetchOne(db, sql: "SELECT dueAt FROM reviewCard WHERE id = ?", arguments: [card.id]),
                state: String.fetchOne(db, sql: "SELECT state FROM reviewCard WHERE id = ?", arguments: [card.id]),
                stateType: String.fetchOne(db, sql: "SELECT typeof(state) FROM reviewCard WHERE id = ?", arguments: [card.id])
            )
        }
        #expect(stored.dueType == "real")
        #expect(stored.dueValue == 1_790_000_000)
        #expect(stored.state == "new")
        #expect(stored.stateType == "text")
    }

    @Test func highlightDeleteCascades() async throws {
        let db = try AppDatabase.makeInMemory()
        let highlight = try await Self.insertHighlight(db)
        let card = TestData.reviewCard(highlightId: highlight.id, id: "57000000-0000-0000-0000-000000000001")
        let log = ReviewLogEntry(
            id: "58000000-0000-0000-0000-000000000001",
            cardId: card.id,
            rating: 3,
            reviewedAt: TestData.referenceDate,
            sessionKind: .daily,
            fsrsLog: "{}"
        )
        let embedding = HighlightEmbedding(
            highlightId: highlight.id,
            modelId: "NLEmbedding.sentence.en",
            dimension: 3,
            vector: ([1, 2, 3] as [Float]).withUnsafeBytes { Data($0) },
            sourceHash: "abc123"
        )

        try await db.writer.write { db in
            try card.insert(db)
            try log.insert(db)
            try embedding.insert(db)
        }

        try await db.writer.write { db in
            _ = try Highlight.deleteOne(db, key: highlight.id)
        }

        let counts = try await db.reader.read { db in
            try (
                cards: Int.fetchOne(db, sql: "SELECT COUNT(*) FROM reviewCard") ?? 0,
                logs: Int.fetchOne(db, sql: "SELECT COUNT(*) FROM reviewLog") ?? 0,
                embeddings: Int.fetchOne(db, sql: "SELECT COUNT(*) FROM highlightEmbedding") ?? 0
            )
        }
        #expect(counts.cards == 0)
        #expect(counts.logs == 0)
        #expect(counts.embeddings == 0)
    }
}
