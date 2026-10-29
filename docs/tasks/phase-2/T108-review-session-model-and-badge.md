# T108: ReviewSessionModel and ReviewBadgeModel

- **Phase:** 2 (E2.2 Daily review; SPEC F-15, F-18 Skip)
- **Agent:** review-engine
- **Depends on:** T105, T106 (`AppSettings.dailyLimits`, `showFourRatingButtons`), T107
- **ADRs:** **ADR-0022** (session in memory, skip, keys, reveal), ADR-0015
- **Visual check needed:** no (the screen is T109)
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 9.

## Goal
The `@MainActor @Observable` logic behind the review screen: load the plan, step through the queue, reveal, rate (keys and buttons), skip, the card actions that change the queue, and the end-of-session summary. Plus the sidebar badge count. Views (T109, T110) stay thin.

## Files to touch
- `StudyReader/Features/Review/Sessions/ReviewSessionModel.swift` (new)
- `StudyReader/Features/Review/Sessions/ReviewBadgeModel.swift` (new)
- `StudyReader/App/AppSession.swift` (modify: `let reviewBadge: ReviewBadgeModel`, created in `init`)
- `StudyReaderTests/ReviewTests/ReviewSessionModelTests.swift` (new)
- `StudyReaderTests/ReviewTests/ReviewBadgeModelTests.swift` (new)

## Interfaces to produce
```swift
struct RatingButton: Sendable, Equatable, Identifiable {
    var rating: ReviewRating
    var title: String          // localized
    var key: Character         // "1"…"4"
    var id: Int { rating.rawValue }
    /// Two buttons: Forgot (.again, "1"), Remembered (.good, "2"). Four: Again 1, Hard 2, Good 3, Easy 4.
    static func buttons(fourButtons: Bool) -> [RatingButton]
}

enum ReviewKeyAction: Sendable, Equatable {
    case reveal
    case rate(ReviewRating)
}

struct ReviewSummary: Sendable, Equatable {
    var reviewed: Int
    var remembered: Int            // ratings other than .again
    var rememberedPercent: Int     // Int((100 * remembered / reviewed).rounded()), 0 when reviewed == 0
    var dueTomorrow: Int           // ReviewService.dueTomorrowCount()
}

@MainActor @Observable
final class ReviewSessionModel {
    enum Phase: Equatable {
        case idle                                    // nothing loaded
        case ready(dueCount: Int, newCount: Int)     // plan loaded, not started; (0, 0) = nothing to review
        case reviewing
        case finished(ReviewSummary)
        case failed(String)                          // user-facing message
    }

    init(session: AppSession, context: ReviewSessionContext = .daily)

    private(set) var phase: Phase = .idle
    private(set) var queue: [ReviewCardItem] = []    // queue.first is the current card
    private(set) var isRevealed = false
    private(set) var isBusy = false                  // a rating or action is being written
    private(set) var position: Int = 0               // cards rated so far this session
    var showOriginal = false                          // reset to false on every card change
    private(set) var errorMessage: String?           // last action error, cleared by the next success

    var current: ReviewCardItem? { get }             // queue.first while reviewing
    var content: ReviewCardContent? { get }          // ReviewCardContent.make(current, showOriginal:)
    var ratingButtons: [RatingButton] { get }        // settings.showFourRatingButtons
    var canRate: Bool { get }                        // reviewing, current != nil, !isBusy, (isRevealed || !content.needsReveal)
    /// "\(position + 1) of \(position + queue.count)", localized. A dropped card (deleted, suspended) lowers the total;
    /// a skip changes nothing.
    var progressText: String { get }

    func loadPlan() async                            // daily: service.dailyPlan(limits: settings.dailyLimits) → .ready
    func start() async                               // items(cardIds:) of the loaded plan → .reviewing (or .finished with 0)
    func reveal()                                    // only when content?.needsReveal == true
    func rate(_ rating: ReviewRating) async
    func skip()
    /// Synchronous, so the view's `.onKeyPress` can answer `.handled`/`.ignored` at once (ADR-0022):
    /// " " → .reveal when content?.needsReveal == true && !isRevealed; "1"…"4" → .rate(r) when canRate and a button
    /// with that key exists; anything else → nil.
    func action(forKey key: Character) -> ReviewKeyAction?
    func perform(_ action: ReviewKeyAction) async     // .reveal → reveal(); .rate(r) → await rate(r)
    func setFrequency(_ override: ReviewFrequency?) async
    func editHighlightText(_ text: String?) async
    func reloadCurrent() async                       // re-reads the current item (after a note edit or Open in Document)
    func endSession()                                 // back to .idle (the view then calls loadPlan)
}

@MainActor @Observable
final class ReviewBadgeModel {
    init(environment: AppEnvironment, settings: AppSettings, calendar: Calendar = .current)
    private(set) var dailyDueCount = 0
    /// Streams reviewCardRepository.observeDailyQueue(now: environment.now, calendar:) and sets
    /// dailyDueCount = DailyReviewBuilder.build(snapshot, limits: settings.dailyLimits).cardIds.count, until cancelled.
    func observe() async
}
```
Behaviour:
- `rate`: guard `canRate`; `isBusy = true`; `try await service.rate(cardId:rating:context:)`; on success count it for the summary (`reviewed += 1`, `remembered += 1` unless `.again`), remove the card from the queue, `position += 1`, `isRevealed = false`, `showOriginal = false`. When the queue is empty: `phase = .finished(summary)` with `dueTomorrow` from the service (0 if that read fails). On `ReviewServiceError.cardMissing` or `.cardSuspended`: drop the card from the queue (not counted) and continue. Any other error: keep the card, set `errorMessage = "The rating couldn't be saved."`.
- `skip`: move the current card to the end; `isRevealed = false`, `showOriginal = false`; nothing written; a one-card queue stays as it is.
- `setFrequency`: `service.setFrequencyOverride`; then re-read the current item; if it is now suspended, drop it like a rating would (not counted; `.finished` when empty). Errors: `errorMessage = "The frequency couldn't be changed."`.
- `editHighlightText`: `service.editHighlightText(highlightId:_:)`, then `reloadCurrent()`. Error: "The highlight couldn't be changed."
- `reloadCurrent`: replace `queue[0]` with the fresh item; a missing item is dropped.
- `context` is stored; T122 adds the themed plan. In this task a `.themed` context makes `loadPlan` set `.failed("Themed reviews aren't available yet.")`.
- `AppSession.init`: `self.reviewBadge = ReviewBadgeModel(environment: environment, settings: settings)`. The view starts `observe()` (T109).
- `AppSession` also keeps the daily session, so it survives the search results replacing the Review section and a switch to another sidebar section (same reason as T85/W2):
  ```swift
  /// The daily review session model, created on first use and kept for the app run (not persisted).
  @ObservationIgnored private var dailyReview: ReviewSessionModel?
  func dailyReviewModel() -> ReviewSessionModel   // returns dailyReview, creating ReviewSessionModel(session: self) once
  ```

## Acceptance criteria
Tests are `@MainActor`, use an in-memory session built on `AppEnvironment.inMemory(now: FixedNow(r))` (`defer { TestFileStore.remove(…) }`), seed documents/highlights/cards through repositories (cards with `ReviewCardFactory`, due states via `recordRating` or direct inserts), and end with `FTSIntegrity.check`. The environment's default `ReviewService` has fuzz on: assert orders and counts, not exact due dates. Tests that change a setting (four buttons, limits) must not use the shared ephemeral suite: build `AppEnvironment(fileStore: store, database: try AppDatabase.makeInMemory(), now: FixedNow(r), settingsStore: TestSettings.make())` with `let store = TestFileStore.make(); try store.createRootDirectories()`, and remove both with `TestFileStore.remove` / `TestSettings.remove` in a `defer`.
1. `ReviewSessionModelTests/planThenStart`: 2 due + 1 new → `.ready(dueCount: 2, newCount: 1)`; `start()` → `.reviewing`, `queue.count == 3`, most overdue first, `progressText == "1 of 3"`.
2. `ReviewSessionModelTests/passiveRatesWithoutReveal` and `ReviewSessionModelTests/masteryNeedsReveal` (a qa card inserted with `ReviewCardFactory.mastery`): `canRate` false until `reveal()` for qa; true at once for passive.
3. `ReviewSessionModelTests/keysMapToButtons` (table, two and four buttons via `session.settings.showFourRatingButtons`): two-button `action(forKey: "1") == .rate(.again)`, "2" → `.rate(.good)`, "3" → nil; four-button "1"…"4" → again…easy; " " → `.reveal` for an unrevealed qa card and nil for a passive card; every key → nil while `canRate` is false (except " " on an unrevealed card); `perform(.rate(.good))` rates the current card.
4. `ReviewSessionModelTests/ratingAdvancesAndFinishes`: rate all three (one `.again`) → `.finished` with reviewed 3, remembered 2, rememberedPercent 67; the database has three logs.
5. `ReviewSessionModelTests/skipMovesCardToEnd` (SPEC F-18 Skip): [a, b, c] → skip → [b, c, a], no log written, `position` unchanged.
6. `ReviewSessionModelTests/missingCardIsDropped`: delete the current card's highlight, then rate → the next card is current, the summary doesn't count it.
7. `ReviewSessionModelTests/frequencyOffRemovesCurrentCard`: `setFrequency(.off)` → card gone from the queue, stored override off.
8. `ReviewSessionModelTests/sessionModelIsKeptBySession`: `session.dailyReviewModel() === session.dailyReviewModel()`.
   `ReviewBadgeModelTests/countsTodaysPlan`: 4 due + 7 new, `newPerDay` 5 → 9; after rating one due card through `ReviewService` the count becomes 8 (`TestWait.until`, `#expect`).
9. `./scripts/test.sh StudyReaderTests/ReviewSessionModelTests StudyReaderTests/ReviewBadgeModelTests StudyReaderTests/AppSessionTests` passes; `./scripts/build.sh` succeeds.

## Out of scope
- Views, focus and key events (T109). Themed plans and completion (T122).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
