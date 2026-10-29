# T121: ThemedReviewBuilder and ThemedReviewSchedule

- **Phase:** 2 (E2.4 Themed reviews; SPEC F-20 AC1, AC2)
- **Agent:** review-engine
- **Depends on:** T98 (`ReviewDay`), T120 (`ThemedQueueSnapshot`)
- **ADRs:** **ADR-0022**, ARCHITECTURE §10.2
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 6.

## Goal
Two pure pieces: which cards a themed session runs (filter → candidates already done by T120; this task orders, excludes and limits), and whether a themed review is due by its interval.

## Files to touch
- `StudyReader/Features/Review/Sessions/ThemedReviewBuilder.swift` (new: `ThemedReviewBuilder`, `ThemedReviewSchedule`, `SeededRandom`)
- `StudyReaderTests/ReviewTests/ThemedReviewBuilderTests.swift` (new)
- `StudyReaderTests/ReviewTests/ThemedReviewScheduleTests.swift` (new)

## Interfaces to produce
```swift
/// SplitMix64. Deterministic for a seed; the service passes a fresh random seed (T122), tests a fixed one.
struct SeededRandom: RandomNumberGenerator, Sendable {
    init(seed: UInt64)
    mutating func next() -> UInt64
}

enum ThemedReviewBuilder {
    /// 1. Drop `snapshot.ratedTodayCardIds`.
    /// 2. dueFirst: cards with dueAt <= now first, by dueAt ASC then cardId; then the rest by lastReviewedAt ASC
    ///    (nil = never reviewed comes first), then dueAt ASC, then cardId.
    ///    random: sort by cardId first (stable input), then `var rng = SeededRandom(seed: seed)` and
    ///    `shuffled(using: &rng)`.
    /// 3. Take review.cardsPerSession.
    static func build(_ snapshot: ThemedQueueSnapshot, review: ThemedReview, now: Date, seed: UInt64) -> [String]
}

enum ThemedReviewSchedule {
    /// SPEC F-20 AC2, ADR-0022 (review days start at 04:00):
    /// - lastCompletedAt == nil: .daily and .everyNDays → true; .weekdays → today's review-day weekday is listed.
    /// - .daily: lastCompletedAt < ReviewDay.start(containing: now).
    /// - .everyNDays(n): ReviewDay.daysBetween(lastCompletedAt, now) >= n (n nil or < 1 counts as 1).
    /// - .weekdays(days): days contains ReviewDay.weekday(of: now) and lastCompletedAt < ReviewDay.start(containing: now).
    static func isDue(_ review: ThemedReview, now: Date, calendar: Calendar) -> Bool
}
```

## Acceptance criteria
Build `ReviewQueueEntry`/`ThemedReview` values directly (no database). UTC calendar; `r = TestData.referenceDate`.
1. `ThemedReviewBuilderTests/dueFirstThenLeastRecentlyReviewed`: due r−2d, due r−1h, future never reviewed, future last reviewed r−10d, future last reviewed r−3d → order: r−2d, r−1h, never reviewed, r−10d, r−3d.
2. `ThemedReviewBuilderTests/volumeLimit` (table): 30 candidates with cardsPerSession 5, 20, 100 → 5, 20, 30.
3. `ThemedReviewBuilderTests/ratedTodayIsExcluded`: two of five candidates rated today → three ids.
4. `ThemedReviewBuilderTests/randomIsSeeded`: same seed → same order; different seeds → a different order for 20 candidates; every id appears once; the limit applies after the shuffle.
5. `ThemedReviewScheduleTests` (table, SPEC F-20 AC2): never completed (daily → due; every 3 days → due; weekdays [Mon] on a Monday → due, on a Tuesday → not); daily completed yesterday 23:00 → due today 05:00, completed today 04:30 → not due at 10:00, completed today 03:00 (still yesterday's review day) → due at 05:00; every 3 days completed 2 review days ago → not, 3 days ago → due; weekdays [Mon, Thu] on Thursday not completed today → due, completed earlier that review day → not, on Wednesday → not.
6. `./scripts/test.sh StudyReaderTests/ThemedReviewBuilderTests StudyReaderTests/ThemedReviewScheduleTests` passes; `./scripts/build.sh` succeeds.

## Out of scope
- Running sessions, completion writes, badges (T122).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
