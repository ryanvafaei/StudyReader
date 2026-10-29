# T122: Themed sessions in ReviewService and ReviewSessionModel; themed badge

- **Phase:** 2 (E2.4 Themed reviews; SPEC F-20 "running a themed review rates the same cards", due badge)
- **Agent:** review-engine
- **Depends on:** T108, T121
- **ADRs:** **ADR-0022** (completion rule, empty selection), ADR-0021
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 8.

## Goal
Run a themed review with the same session model as the daily review: its plan comes from `ThemedReviewBuilder`, ratings are logged as themed with the review's id, and a session whose queue empties through ratings marks the review completed. The Themed Reviews sidebar row gets a badge with the number of due themed reviews.

## Files to touch
- `StudyReader/Features/Review/Sessions/ReviewService.swift` (modify: themed plan, completion)
- `StudyReader/Features/Review/Sessions/ReviewSessionModel.swift` (modify: `.themed` context)
- `StudyReader/Features/Review/Sessions/ReviewBadgeModel.swift` (modify: `themedDueCount`)
- `StudyReader/App/AppEnvironment.swift` (modify: pass `themedReviewRepository` to `ReviewService`)
- `StudyReaderTests/ReviewTests/ThemedSessionTests.swift` (new)
- `StudyReaderTests/ReviewTests/ReviewBadgeModelTests.swift` (modify: one test)
- Test files that build a `ReviewService` directly (modify: the new init argument only)

## Interfaces to produce
```swift
actor ReviewService {
    // init gains `themedReviews: ThemedReviewRepository` and `makeSeed: @escaping @Sendable () -> UInt64 =
    // { UInt64.random(in: .min ... .max) }` (tests pass a fixed seed). Update the AppEnvironment call and every
    // existing `ReviewService(…)` call in tests (Grep `ReviewService(` in StudyReaderTests: T105, T108, T111, T115
    // suites); add those suites to the test filter of criterion 8 if they aren't there.

    /// Missing review → ThemedReviewError.notFound. Snapshot = themedReviews.themedQueue(filter:, dayStart:
    /// ReviewDay.start(containing: now(), calendar:)); ids = ThemedReviewBuilder.build(…, now: now(), seed: makeSeed()).
    func themedPlan(reviewId: String) async throws -> (review: ThemedReview, cardIds: [String])
    /// themedReviews.markCompleted(id:at: now()).
    func completeThemedReview(id: String) async throws
}

// ReviewSessionModel, context .themed(id:):
// - loadPlan(): themedPlan(reviewId:) → themedReviewName = review.name, phase .ready(dueCount: ids.count, newCount: 0)
//   (a themed session shows only its total). Zero ids → completeThemedReview(id:) at once (ADR-0022) and
//   phase .finished(ReviewSummary(reviewed: 0, remembered: 0, rememberedPercent: 0, dueTomorrow: <service value>)).
//   This replaces T108's "Themed reviews aren't available yet." placeholder message.
// - ratings use context .themed(id:) (ReviewService already logs kind and id, T105).
// - when the queue becomes empty after a rating: completeThemedReview(id:) (errors → errorMessage, the summary
//   still shows), then .finished.
private(set) var themedReviewName: String?

@MainActor @Observable final class ReviewBadgeModel {
    private(set) var themedDueCount = 0
    /// Streams themedReviewRepository.observeAll() and counts ThemedReviewSchedule.isDue(_, now: environment.now(), calendar:).
    func observeThemed() async
}
```
- Leaving a themed session early (`endSession()`) never marks it completed.
- The daily session model stays as it is; a themed session model is a separate `ReviewSessionModel(session:context:)` instance created by the Themed Reviews section (T124).

## Acceptance criteria
`@MainActor` where models are used; in-memory environment on `FixedNow(r)` with a UTC calendar; a service built with `ReviewScheduler(enableFuzz: false)` and a fixed seed; end with `FTSIntegrity.check`.
1. `ThemedSessionTests/planFollowsFilterAndVolume`: a themed review over tag "exam" with cardsPerSession 5 and 8 matching cards → 5 ids, all exam cards, due first.
2. `ThemedSessionTests/ratingsAreLoggedAsThemed`: rate a card in the themed session → its log has `sessionKind == .themed` and `themedReviewId == review.id`; the card's FSRS state changed (one state per card).
3. `ThemedSessionTests/themedRatedCardsLeaveTodaysDailyReview` (SPEC F-20): a card due today rated in the themed session is not in `dailyPlan` the same review day, and is back when due on a later day.
4. `ThemedSessionTests/finishingMarksCompleted`: rate every card → `lastCompletedAt == r`; `ThemedReviewSchedule.isDue` (daily) false for the rest of the review day, true after the next 04:00.
5. `ThemedSessionTests/leavingEarlyDoesNotComplete`: rate one of three, `endSession()` → `lastCompletedAt` nil.
6. `ThemedSessionTests/emptySelectionCompletesAtOnce`: a filter matching nothing → `.finished` with reviewed 0 and `lastCompletedAt == r`.
7. `ReviewBadgeModelTests/countsDueThemedReviews`: two reviews (one never completed, one completed today, both daily) → `themedDueCount == 1`; after completing the first → 0 (`TestWait.until`, `#expect`).
8. `./scripts/test.sh StudyReaderTests/ThemedSessionTests StudyReaderTests/ReviewBadgeModelTests StudyReaderTests/ReviewServiceTests StudyReaderTests/ReviewActionsTests StudyReaderTests/ReviewSessionModelTests StudyReaderTests/SampleLibraryTests StudyReaderTests/MasteryServiceTests` passes; `./scripts/build.sh` succeeds.

## Out of scope
- The Themed Reviews section UI and the sidebar badge view (T124).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
- 2026-10-29, implementer review-engine haiku medium, reviewer code-reviewer sonnet medium: CHANGES REQUESTED (1st), production code correct; tests miss spec assertions: themedRatedCardsLeaveTodaysDailyReview never shows the card back on a later day; finishingMarksCompleted does not assert ThemedReviewSchedule.isDue false for the rest of the day / true after next 04:00; minor: due-first not asserted, FSRS state change not asserted; test-only rework
- 2026-10-29, implementer review-engine haiku high (rework 1, test-only, effort high), reviewer code-reviewer sonnet high: APPROVED, all four findings fixed, instants re-derived against the 05:00 session time, production files unchanged; CI build and full unit tests green, 919 tests (runs 40948651568, 40949052385)
