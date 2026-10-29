# T102: Rating writes, review log and the daily queue query

- **Phase:** 2 (E2.2 Daily review; SPEC F-15 AC1 persistence part, F-20 "not shown again the same day")
- **Agent:** data-layer
- **Depends on:** T99
- **ADRs:** ADR-0012 (dates in SQL: always `.databaseUnixSeconds`), ADR-0013, **ADR-0021** (`introducedAt`), **ADR-0022** (review day, budgets)
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 8.

## Goal
The reads and the one write a review session needs: lightweight queue rows for the builder (no highlight text), today's activity, full card items for display, and the rating transaction (card + log). The builder that picks cards is T104; this task only reads and writes.

## Files to touch
- `StudyReader/Core/Repositories/ReviewQueue.swift` (new: the value types below and `enum ReviewQueueSQL` with the static SQL functions, `(_ db: Database, …) throws`, the same split as `HighlightBrowseSQL`)
- `StudyReader/Core/Repositories/ReviewCardRepository.swift` (modify: the thin `async` methods below, each one `writer.read`/`writer.write` calling `ReviewQueueSQL`; `writer` stays `private`)
- `StudyReaderTests/CoreTests/ReviewQueueTests.swift` (new)

## Interfaces to produce
```swift
// Core/Repositories/ReviewQueue.swift
/// One card row for the session builders. No highlight text.
struct ReviewQueueEntry: Sendable, Equatable, Identifiable {
    var cardId: String
    var highlightId: String
    var cardType: CardType
    var state: ReviewCardState
    var dueAt: Date
    var introducedAt: Date?
    var highlightCreatedAt: Date
    /// MAX(reviewLog.reviewedAt) of this card, nil if never rated.
    var lastReviewedAt: Date?
    var id: String { cardId }
}

/// What happened since the start of the current review day.
struct ReviewDayActivity: Sendable, Equatable {
    var ratedCardIds: Set<String> = []          // any session kind, reviewedAt >= dayStart
    var dailyRatedCardIds: Set<String> = []     // sessionKind 'daily', reviewedAt >= dayStart
    var themedRatedCardIds: Set<String> = []    // sessionKind 'themed', reviewedAt >= dayStart
    var introducedCardIds: Set<String> = []     // introducedAt >= dayStart
}

struct DailyQueueSnapshot: Sendable, Equatable {
    /// Not suspended, state != new, dueAt <= now. Ordered dueAt ASC, cardId ASC.
    var due: [ReviewQueueEntry]
    /// Not suspended, state == new, introducedAt IS NULL. Ordered highlight createdAt ASC, cardId ASC.
    var new: [ReviewQueueEntry]
    var activity: ReviewDayActivity
}

/// One card with what the review screen shows.
struct ReviewCardItem: Sendable, Equatable, Identifiable {
    var card: ReviewCard
    var highlight: Highlight
    var documentTitle: String
    var categoryFrequency: ReviewFrequency
    /// Sorted case-insensitively (same order as HighlightListItem.tagNames).
    var tagNames: [String]
    var id: String { card.id }
}

/// Everything one rating writes (built by ReviewService, T105).
struct RatingWrite: Sendable, Equatable {
    var cardId: String
    var fsrsCard: String            // StoredFSRSCard JSON after the review
    var dueAt: Date                 // == that card's due (storage-rounded)
    var state: ReviewCardState
    var reviewedAt: Date
    var rating: ReviewRating
    var sessionKind: ReviewSessionKind
    var themedReviewId: String?     // non-nil only for .themed
    var fsrsLog: String             // StoredFSRSLog JSON
}

// ReviewCardRepository.swift (new methods)
extension ReviewCardRepository {
    /// One read: both candidate lists and the activity. `dayStart` comes from ReviewDay.start(containing:calendar:).
    func dailyQueue(now: Date, dayStart: Date) async throws -> DailyQueueSnapshot
    /// Live version: re-runs on every change to reviewCard, reviewLog, highlight, document or category, calling
    /// `now()` and ReviewDay.start(containing: now(), calendar: calendar) inside the tracking closure on each run.
    func observeDailyQueue(now: any Now, calendar: Calendar) -> AsyncValueObservation<DailyQueueSnapshot>
    /// Full items in the given order; ids without a card are skipped. One query for the rows, one for the tag names.
    func items(cardIds: [String]) async throws -> [ReviewCardItem]
    func item(cardId: String) async throws -> ReviewCardItem?
    /// One transaction. Missing card → RepositoryError.notFound (nothing written). Updates fsrsCard, dueAt, state, and
    /// introducedAt = reviewedAt only when it is NULL, with update(db, columns: [...]); inserts
    /// ReviewLogEntry(id: UUID().uuidString, cardId, rating: rating.rawValue, reviewedAt, sessionKind, themedReviewId, fsrsLog).
    /// Returns the log entry.
    @discardableResult
    func recordRating(_ write: RatingWrite) async throws -> ReviewLogEntry
    /// Cards not suspended, state != new, dueAt < date (for the summary's "due tomorrow", T105).
    func dueCount(before date: Date) async throws -> Int
}
```
- Bind every date as `date.databaseUnixSeconds` (ADR-0012): `dueAt <= ?`, `reviewedAt >= ?`, `introducedAt >= ?`, `dueAt < ?`.
- `lastReviewedAt` with a grouped subquery or `LEFT JOIN (SELECT cardId, MAX(reviewedAt) AS lastReviewedAt FROM reviewLog GROUP BY cardId)`; the `reviewLog_card` index covers it.
- `items(cardIds:)`: join `reviewCard` → `highlight` → `document` → `category`; tags via `highlightTag`/`tag` in one extra query; return in the order of `cardIds`.

## Acceptance criteria
Tests use an in-memory database, `TestData` records, cards inserted with `insert(db)` and explicit `state`/`dueAt`/`introducedAt`/`suspended`, fixed dates from `TestData.referenceDate` (`r`), and `dayStart = r - 3600`. End with `FTSIntegrity.check`.
1. `ReviewQueueTests/dailyQueueSplitsDueAndNew`: cards: review due r−2d, review due r−1h, review due r+1d (not due), relearning due r−3d, new (introducedAt nil), new with introducedAt set, suspended review due r−5d. `due` = [relearning, r−2d, r−1h] in that order; `new` = the one never introduced; the suspended and future cards appear in neither.
2. `ReviewQueueTests/newOrderedByHighlightCreation`: three new cards whose highlights were created r−1d, r−3d, r−2d → order r−3d, r−2d, r−1d; ties by cardId.
3. `ReviewQueueTests/activityCountsToday`: logs at dayStart−1 s (daily), dayStart (daily), r (themed) and a card with introducedAt = dayStart + 10 → `ratedCardIds` has the two from today only, `dailyRatedCardIds`/`themedRatedCardIds` split them, `introducedCardIds` has the introduced card; `lastReviewedAt` of a card with two logs is the later one.
4. `ReviewQueueTests/recordRatingWritesCardAndLog`: rate a new card: card `fsrsCard`, `dueAt`, `state` updated, `introducedAt == reviewedAt`; one `reviewLog` row with `rating == 3` for `.good`, the session kind, `themedReviewId`, `fsrsLog`; a second rating keeps the first `introducedAt`; an unknown card id throws `.notFound` and inserts no log.
5. `ReviewQueueTests/themedRatingKeepsReviewId`: `.themed` with a `ThemedReview` row id → the log has that id; deleting the themed review sets it to NULL (FK `ON DELETE SET NULL`, already in the schema).
6. `ReviewQueueTests/itemsKeepOrderAndCarryDisplayData`: `items(cardIds: [b, unknown, a])` returns [b, a] with the right highlight, document title, category frequency and sorted tag names; `item(cardId:)` of a missing id is nil.
7. `ReviewQueueTests/observeDailyQueueReactsToRatings`: the observation's first value has one due card; after `recordRating` (due moves to r+3d) a later value has none (`TestWait.until`, `#expect`). `ReviewQueueTests/dueCountBefore`: counts only non-suspended, non-new cards due before the date.
8. `./scripts/test.sh StudyReaderTests/ReviewQueueTests StudyReaderTests/ReviewCardRepositoryTests` passes; `./scripts/build.sh` succeeds.
9. Reviewer Grep: no bare `Date` bound in SQL or `arguments:` in the new files.

## Out of scope
- Choosing the session's cards (T104), FSRS (T105 builds `RatingWrite`), themed-review filters (T120).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
