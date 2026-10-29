import Testing
import Foundation
@testable import StudyReader

/// Daily session builder (T104, SPEC F-15/F-20, ADR-0022). Entries are built directly; no database.
@Suite struct DailyReviewBuilderTests {

    private static let r = TestData.referenceDate
    private static let day: TimeInterval = 86_400

    private static func newEntry(
        _ id: String,
        type: CardType = .passive,
        createdAt: Date = r
    ) -> ReviewQueueEntry {
        ReviewQueueEntry(
            cardId: id,
            highlightId: "h-\(id)",
            cardType: type,
            state: .new,
            dueAt: r,
            introducedAt: nil,
            highlightCreatedAt: createdAt,
            lastReviewedAt: nil
        )
    }

    private static func dueEntry(_ id: String, dueAt: Date) -> ReviewQueueEntry {
        ReviewQueueEntry(
            cardId: id,
            highlightId: "h-\(id)",
            cardType: .passive,
            state: .review,
            dueAt: dueAt,
            introducedAt: r - 30 * day,
            highlightCreatedAt: r - 30 * day,
            lastReviewedAt: dueAt
        )
    }

    @Test func dueFirstMostOverdueFirst() {
        let snapshot = DailyQueueSnapshot(
            due: [
                Self.dueEntry("d2h", dueAt: Self.r - 2 * 3600),
                Self.dueEntry("d1d", dueAt: Self.r - Self.day),
                Self.dueEntry("d5d", dueAt: Self.r - 5 * Self.day),
            ],
            new: [
                Self.newEntry("new-b"),
                Self.newEntry("new-a"),
            ],
            activity: ReviewDayActivity()
        )
        let plan = DailyReviewBuilder.build(snapshot, limits: .defaults)
        #expect(plan.cardIds == ["d5d", "d1d", "d2h", "new-a", "new-b"])
        #expect(plan.dueCount == 3)
        #expect(plan.newCount == 2)
    }

    @Test func limitsAreRespected() {
        let cases: [(dailyLimit: Int, newPerDay: Int, expectedDue: Int, expectedNew: Int)] = [
            (15, 5, 15, 5),
            (3, 0, 3, 0),
            (0, 5, 0, 5),
            (-1, -4, 0, 0),
            (15, -2, 15, 0),
            (-3, 5, 0, 5),
        ]
        let due = (0..<20).map { Self.dueEntry("due-\($0)", dueAt: Self.r - Double($0 + 1) * 60) }
        let new = (0..<10).map { Self.newEntry("new-\($0)", createdAt: Self.r - Double($0 + 1) * 60) }
        for testCase in cases {
            let snapshot = DailyQueueSnapshot(due: due, new: new, activity: ReviewDayActivity())
            let plan = DailyReviewBuilder.build(
                snapshot,
                limits: DailyLimits(dailyLimit: testCase.dailyLimit, newPerDay: testCase.newPerDay)
            )
            #expect(plan.dueCount == testCase.expectedDue)
            #expect(plan.newCount == testCase.expectedNew)
            #expect(plan.cardIds.count == testCase.expectedDue + testCase.expectedNew)
        }
    }

    @Test func budgetsAreForTheWholeDay() {
        // 10 cards rated in daily sessions today, 2 of them introduced today (d1, d2).
        // 4 cards introduced today in any session (d1, d2, t1, t2).
        let dailyRated = (1...10).map { "d\($0)" }
        let activity = ReviewDayActivity(
            ratedCardIds: Set(dailyRated + ["t1", "t2"]),
            dailyRatedCardIds: Set(dailyRated),
            themedRatedCardIds: ["t1", "t2"],
            introducedCardIds: ["d1", "d2", "t1", "t2"]
        )
        let snapshot = DailyQueueSnapshot(
            due: (0..<20).map { Self.dueEntry("due-\($0)", dueAt: Self.r - Double($0 + 1) * 60) },
            new: (0..<3).map { Self.newEntry("new-\($0)", createdAt: Self.r - Double($0 + 1) * 60) },
            activity: activity
        )
        let plan = DailyReviewBuilder.build(snapshot, limits: .defaults)
        #expect(plan.dueCount == 7)
        #expect(plan.newCount == 1)
    }

    @Test func ratedTodayIsExcluded() {
        let activity = ReviewDayActivity(
            ratedCardIds: ["dueThemed", "dueDaily", "newRated"],
            dailyRatedCardIds: ["dueDaily"],
            themedRatedCardIds: ["dueThemed"],
            introducedCardIds: []
        )
        let snapshot = DailyQueueSnapshot(
            due: [
                Self.dueEntry("dueThemed", dueAt: Self.r - Self.day),
                Self.dueEntry("dueDaily", dueAt: Self.r - 2 * Self.day),
                Self.dueEntry("dueFree", dueAt: Self.r - 3 * Self.day),
            ],
            new: [
                Self.newEntry("newRated"),
                Self.newEntry("newFree"),
            ],
            activity: activity
        )
        let plan = DailyReviewBuilder.build(snapshot, limits: .defaults)
        #expect(plan.cardIds == ["dueFree", "newFree"])
        #expect(plan.dueCount == 1)
        #expect(plan.newCount == 1)
    }

    @Test func newCardOrder() {
        let snapshot = DailyQueueSnapshot(
            due: [],
            new: [
                Self.newEntry("p1", type: .passive, createdAt: Self.r - Self.day),
                Self.newEntry("q", type: .qa, createdAt: Self.r - 3 * Self.day),
                Self.newEntry("p3", type: .passive, createdAt: Self.r - 3 * Self.day),
                Self.newEntry("c", type: .cloze, createdAt: Self.r - 3 * Self.day),
            ],
            activity: ReviewDayActivity()
        )
        let plan = DailyReviewBuilder.build(snapshot, limits: DailyLimits(dailyLimit: 15, newPerDay: 10))
        #expect(plan.cardIds == ["p3", "c", "q", "p1"])
        #expect(plan.newCount == 4)
    }

    @Test func emptySnapshot() {
        let snapshot = DailyQueueSnapshot(due: [], new: [], activity: ReviewDayActivity())
        let plan = DailyReviewBuilder.build(snapshot, limits: .defaults)
        #expect(plan.isEmpty)
        #expect(plan.cardIds.isEmpty)
        #expect(plan.dueCount == 0)
        #expect(plan.newCount == 0)
    }
}
