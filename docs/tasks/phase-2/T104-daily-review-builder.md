# T104: DailyReviewBuilder

- **Phase:** 2 (E2.2 Daily review; SPEC F-15 AC2)
- **Agent:** review-engine
- **Depends on:** T98, T102 (`DailyQueueSnapshot`)
- **ADRs:** **ADR-0022** (budgets per review day), ARCHITECTURE §10.2
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 4.

## Goal
The pure function that picks today's daily session from the repository's snapshot: due cards first (most overdue first) up to the day's remaining due budget, then new cards (oldest highlight first) up to the remaining new budget.

## Files to touch
- `StudyReader/Features/Review/Sessions/DailyReviewBuilder.swift` (new)
- `StudyReaderTests/ReviewTests/DailyReviewBuilderTests.swift` (new)

## Interfaces to produce
```swift
/// Settings > Review values (SPEC F-15 defaults 15 and 5). AppSettings.dailyLimits builds it (T106).
struct DailyLimits: Sendable, Equatable {
    var dailyLimit: Int
    var newPerDay: Int
    static let defaults = DailyLimits(dailyLimit: 15, newPerDay: 5)
}

struct DailyReviewPlan: Sendable, Equatable {
    /// Due cards first, then new cards.
    var cardIds: [String]
    var dueCount: Int
    var newCount: Int
    var isEmpty: Bool { cardIds.isEmpty }
}

enum DailyReviewBuilder {
    static func build(_ snapshot: DailyQueueSnapshot, limits: DailyLimits) -> DailyReviewPlan
}
```
Rules (ADR-0022), in this order:
1. `rated = snapshot.activity.ratedCardIds`.
2. Due budget: `max(0, limits.dailyLimit − (activity.dailyRatedCardIds − activity.introducedCardIds).count)`.
3. Due cards: `snapshot.due` without `rated`, sorted by `dueAt` ascending, then `cardId` ascending; take the due budget.
4. New budget: `max(0, limits.newPerDay − activity.introducedCardIds.count)`.
5. New cards: `snapshot.new` without `rated`, sorted by `highlightCreatedAt` ascending, then passive before cloze before qa, then `cardId`; take the new budget.
6. `cardIds` = due ids then new ids. Negative limits behave like 0.
Sort in the builder even though the repository already orders: the builder is the contract tests pin.

## Acceptance criteria
Table-driven; build `ReviewQueueEntry` values directly (no database). `r = TestData.referenceDate`.
1. `DailyReviewBuilderTests/dueFirstMostOverdueFirst`: due at r−1d, r−5d, r−2h and two new cards → ids: r−5d, r−1d, r−2h, then the new ones.
2. `DailyReviewBuilderTests/limitsAreRespected` (table): 20 due + 10 new with defaults → 15 + 5; `dailyLimit` 3 / `newPerDay` 0 → 3 + 0; `dailyLimit` 0 → only new; negative values → 0.
3. `DailyReviewBuilderTests/budgetsAreForTheWholeDay`: activity with 10 daily-rated cards (2 of them introduced today) and 4 introduced today → due budget 15 − 8 = 7, new budget 5 − 4 = 1.
4. `DailyReviewBuilderTests/ratedTodayIsExcluded`: a due card in `themedRatedCardIds`/`ratedCardIds` and a new card in `ratedCardIds` are left out (SPEC F-20 "not shown again in daily review the same day").
5. `DailyReviewBuilderTests/newCardOrder`: new cards from highlights created r−1d (passive), r−3d (qa), r−3d (passive), r−3d (cloze) → r−3d passive, r−3d cloze, r−3d qa, r−1d passive.
6. `DailyReviewBuilderTests/emptySnapshot`: empty plan, `isEmpty`.
7. `./scripts/test.sh StudyReaderTests/DailyReviewBuilderTests` passes; `./scripts/build.sh` succeeds.

## Out of scope
- Reading the database (T105 calls the repository). Themed reviews (T121).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
