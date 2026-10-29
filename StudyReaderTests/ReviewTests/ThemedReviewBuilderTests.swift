import Testing
import Foundation
@testable import StudyReader

/// Themed session ordering, limits and exclusion (T121, SPEC F-20, ADR-0022). Fixed dates, no database.
@Suite struct ThemedReviewBuilderTests {

    private static let r = TestData.referenceDate

    private static func entry(
        _ id: String,
        dueAt: Date,
        lastReviewedAt: Date? = nil
    ) -> ReviewQueueEntry {
        ReviewQueueEntry(
            cardId: id,
            highlightId: "h-\(id)",
            cardType: .passive,
            state: .review,
            dueAt: dueAt,
            introducedAt: r,
            highlightCreatedAt: r,
            lastReviewedAt: lastReviewedAt
        )
    }

    private static func review(
        cardsPerSession: Int = 20,
        orderMode: ReviewOrderMode = .dueFirst
    ) -> ThemedReview {
        ThemedReview(
            id: "t-1",
            name: "Test",
            cardsPerSession: cardsPerSession,
            orderMode: orderMode,
            createdAt: r
        )
    }

    private static func snapshot(
        _ candidates: [ReviewQueueEntry],
        ratedToday: Set<String> = []
    ) -> ThemedQueueSnapshot {
        ThemedQueueSnapshot(candidates: candidates, ratedTodayCardIds: ratedToday)
    }

    @Test func dueFirstThenLeastRecentlyReviewed() {
        let candidates = [
            Self.entry("c-future-recent", dueAt: Self.r.addingTimeInterval(86_400), lastReviewedAt: Self.r.addingTimeInterval(-3 * 86_400)),
            Self.entry("c-due-old", dueAt: Self.r.addingTimeInterval(-2 * 86_400)),
            Self.entry("c-future-never", dueAt: Self.r.addingTimeInterval(2 * 86_400)),
            Self.entry("c-due-hour", dueAt: Self.r.addingTimeInterval(-3_600)),
            Self.entry("c-future-old", dueAt: Self.r.addingTimeInterval(3 * 86_400), lastReviewedAt: Self.r.addingTimeInterval(-10 * 86_400)),
        ]

        let ids = ThemedReviewBuilder.build(Self.snapshot(candidates), review: Self.review(), now: Self.r, seed: 1)

        #expect(ids == ["c-due-old", "c-due-hour", "c-future-never", "c-future-old", "c-future-recent"])
    }

    @Test func volumeLimit() {
        let candidates = (0..<30).map { Self.entry(String(format: "c-%02d", $0), dueAt: Self.r.addingTimeInterval(Double($0))) }
        let cases: [(limit: Int, expected: Int)] = [(5, 5), (20, 20), (100, 30)]

        for testCase in cases {
            let ids = ThemedReviewBuilder.build(
                Self.snapshot(candidates),
                review: Self.review(cardsPerSession: testCase.limit),
                now: Self.r,
                seed: 1
            )
            #expect(ids.count == testCase.expected, "limit \(testCase.limit)")
        }
    }

    @Test func ratedTodayIsExcluded() {
        let candidates = (0..<5).map { Self.entry("c-\($0)", dueAt: Self.r.addingTimeInterval(Double(-$0 - 1))) }
        let ids = ThemedReviewBuilder.build(
            Self.snapshot(candidates, ratedToday: ["c-0", "c-3"]),
            review: Self.review(),
            now: Self.r,
            seed: 1
        )

        #expect(ids == ["c-4", "c-2", "c-1"])
    }

    @Test func randomIsSeeded() {
        let candidates = (0..<20).map { Self.entry("c-\(String(format: "%02d", $0))", dueAt: Self.r.addingTimeInterval(Double($0))) }
        let all = Self.snapshot(candidates)
        let randomReview = Self.review(cardsPerSession: 100, orderMode: .random)

        let first = ThemedReviewBuilder.build(all, review: randomReview, now: Self.r, seed: 42)
        let again = ThemedReviewBuilder.build(all, review: randomReview, now: Self.r, seed: 42)
        let other = ThemedReviewBuilder.build(all, review: randomReview, now: Self.r, seed: 7)

        #expect(first == again)
        #expect(first != other)
        #expect(Set(first).count == 20)
        #expect(first.count == 20)
        #expect(Set(first) == Set(candidates.map(\.cardId)))

        // The limit applies after the shuffle: a short session is the start of the full shuffled order.
        let limited = ThemedReviewBuilder.build(
            all,
            review: Self.review(cardsPerSession: 5, orderMode: .random),
            now: Self.r,
            seed: 42
        )
        #expect(limited == Array(first.prefix(5)))
    }

    @Test func splitMixMatchesReferenceSequence() {
        // Reference values of SplitMix64 for seed 0 (standard constants).
        var rng = SeededRandom(seed: 0)
        #expect(rng.next() == 0xE220_A839_7B1D_CDAF)
        #expect(rng.next() == 0x6E78_9E6A_A1B9_65F4)
    }
}
