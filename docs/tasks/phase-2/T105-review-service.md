# T105: ReviewService: daily plan, rating and review actions

- **Phase:** 2 (E2.2 Daily review; SPEC F-15 AC1, F-18 AC1)
- **Agent:** review-engine
- **Depends on:** T97, T103, T104
- **ADRs:** ADR-0006, **ADR-0021**, **ADR-0022**
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 9.

## Goal
One actor that the review UI models call: build the daily plan, load the cards, rate a card (FSRS + one write), change a card's frequency (reschedule from the last review, suspend on Off) and edit the highlight's display text. It owns the `ReviewScheduler`, the injected clock and the calendar.

## Files to touch
- `StudyReader/Features/Review/Sessions/ReviewService.swift` (new)
- `StudyReader/App/AppEnvironment.swift` (modify: `let reviewService: ReviewService`)
- `StudyReaderTests/ReviewTests/ReviewServiceTests.swift` (new)
- `StudyReaderTests/ReviewTests/ReviewActionsTests.swift` (new; SPEC F-18 AC1 names `ReviewActionsTests/*`)

## Interfaces to produce
```swift
enum ReviewSessionContext: Sendable, Equatable {
    case daily
    case themed(id: String)       // used from T122 on
    var sessionKind: ReviewSessionKind { get }   // .daily / .themed
    var themedReviewId: String? { get }
}

struct RatingOutcome: Sendable, Equatable {
    var card: ReviewCard          // after the write
    var log: ReviewLogEntry
}

enum ReviewServiceError: Error, Equatable, LocalizedError {
    case cardMissing              // "This card no longer exists."
    case cardSuspended            // "This card is suspended."
}

actor ReviewService {
    init(cards: ReviewCardRepository, highlights: HighlightRepository, now: any Now,
         calendar: Calendar = .current, scheduler: ReviewScheduler = ReviewScheduler())

    /// dailyQueue(now: now(), dayStart: ReviewDay.start(containing: now(), calendar:)) → DailyReviewBuilder.build.
    func dailyPlan(limits: DailyLimits) async throws -> DailyReviewPlan
    func items(cardIds: [String]) async throws -> [ReviewCardItem]
    func item(cardId: String) async throws -> ReviewCardItem?

    /// Reads the item fresh (missing → .cardMissing); suspended or retention nil → .cardSuspended. Retention =
    /// FrequencyPolicy.retention(override: card.frequencyOverride, category: item.categoryFrequency). Decodes
    /// StoredFSRSCard(json: card.fsrsCard), scheduler.schedule(…, now: now()), then cards.recordRating(RatingWrite(…))
    /// with dueAt = the new card's due, reviewedAt = now(), the context's kind and themed id. Returns the stored card
    /// (fetched after the write) and the log.
    func rate(cardId: String, rating: ReviewRating, context: ReviewSessionContext) async throws -> RatingOutcome

    /// SPEC F-18 "Change frequency". New retention = FrequencyPolicy.retention(override:category: item.categoryFrequency).
    /// When it is non-nil and the card is not new and has a lastReview: rescheduled = card with due =
    /// scheduler.rescheduledDue(card, retention:) and scheduledDays = whole days from lastReview to that due; else nil.
    /// Then cards.updateFrequencyOverride(cardId:override:rescheduled:). Missing → .cardMissing.
    func setFrequencyOverride(cardId: String, _ override: ReviewFrequency?) async throws

    /// SPEC F-18 "Edit highlight": highlights.updateEditedText(id:editedText:at: now()).
    func editHighlightText(highlightId: String, _ text: String?) async throws

    /// Cards due before the end of tomorrow's review day: cards.dueCount(before: start(after: now) + 1 day).
    func dueTomorrowCount() async throws -> Int
}
```
- `AppEnvironment.init`: `self.reviewService = ReviewService(cards: reviewCardRepository, highlights: highlightRepository, now: now)`. The default `ReviewScheduler()` has fuzz on (ADR-0021); tests build their own service with `ReviewScheduler(enableFuzz: false)`, a `FixedNow` and a UTC calendar.
- Never call `Date()`; every time comes from `now()`.

## Acceptance criteria
Tests use an in-memory `AppEnvironment(…, now: FixedNow(r))` (`defer { TestFileStore.remove(…) }`; T96 makes future clocks safe), their own `ReviewService(…, calendar: utc, scheduler: ReviewScheduler(enableFuzz: false))`, cards from `ReviewCardFactory`, and end with `FTSIntegrity.check`.
1. `ReviewServiceTests/ratingUpdatesCardAndLogsReview` (SPEC F-15 AC1): rating a new card good → stored `state == .review`, `dueAt` equals what `ReviewScheduler(enableFuzz: false).schedule` returns for the same input, `introducedAt == r`, one log with rating 3, `sessionKind == .daily`, `fsrsLog` decodes to a `StoredFSRSLog` with `state == .new`.
2. `ReviewServiceTests/dailyPlanUsesTheDayBoundary`: a card rated at 03:00 (before the 04:00 boundary) and the clock moved to 05:00 the same calendar day → the activity counts it as yesterday's (budget not reduced).
3. `ReviewServiceTests/rateRejectsSuspendedAndMissing`: `.cardSuspended` for a suspended card, `.cardMissing` after deleting the highlight.
4. `ReviewServiceTests/persistsAcrossANewService`: rate two of three planned cards, build a new `ReviewService` on the same database: its plan contains only the third card (SPEC F-15 AC3, logic part).
5. `ReviewActionsTests/frequencyChangeReschedulesFromLastReview`: a card rated good (lastReview L) in a Normal category; `.high` → `dueAt == scheduler.rescheduledDue(card, retention: 0.95)` and earlier than before; `.low` → later; nil → back to the 0.90 due.
6. `ReviewActionsTests/frequencyOffSuspendsAndLeavesThePlan`: `.off` → card `.user`-suspended and not in `dailyPlan`; `.normal` → back in the plan when due.
7. `ReviewActionsTests/newCardFrequencyChangeKeepsDue`: a new card's `dueAt` is unchanged by any override.
8. `ReviewActionsTests/editHighlightTextKeepsOriginal`: edit → `editedText` set, `text` unchanged; "" → nil. `ReviewActionsTests/noteEditPersists`: `NoteEditorModel(target: .highlight(id), environment:)` load, set text, `flush()` → the highlight's note is stored (the review screen reuses this editor). Skip is tested in T108 (`ReviewSessionModelTests/skipMovesCardToEnd`).
9. `./scripts/test.sh StudyReaderTests/ReviewServiceTests StudyReaderTests/ReviewActionsTests StudyReaderTests/AppEnvironmentTests` passes; `./scripts/build.sh` succeeds.

## Out of scope
- Themed plans (T122), Mastery (T115), UI models (T108).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
