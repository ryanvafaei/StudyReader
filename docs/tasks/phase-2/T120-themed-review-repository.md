# T120: ThemedReviewRepository

- **Phase:** 2 (E2.4 Themed reviews; SPEC F-20)
- **Agent:** data-layer
- **Depends on:** T102 (`ReviewQueueEntry`, `ReviewQueueSQL`)
- **ADRs:** ADR-0012, **ADR-0022** (completion, rated today)
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 8.

## Goal
Store themed reviews (create, edit, duplicate, delete, mark completed) and read the candidate cards for a themed review's filter. The `themedReview` table and its JSON columns already exist (`ThemedReview`, `ThemedReviewFilter`, `ReviewInterval`, `ReviewOrderMode`).

## Files to touch
- `StudyReader/Core/Repositories/ThemedReviewRepository.swift` (new)
- `StudyReader/Core/Repositories/ReviewQueue.swift` (modify: one SQL function for the themed candidates, reusing the row mapping of T102)
- `StudyReader/App/AppEnvironment.swift` (modify: `let themedReviewRepository: ThemedReviewRepository`)
- `StudyReaderTests/CoreTests/ThemedReviewRepositoryTests.swift` (new)

## Interfaces to produce
```swift
/// What the editor (T123) hands over.
struct ThemedReviewDraft: Sendable, Equatable {
    var name: String
    var filter: ThemedReviewFilter = ThemedReviewFilter()
    var cardsPerSession: Int = 20
    var interval: ReviewInterval = .daily
    var orderMode: ReviewOrderMode = .dueFirst
    init(name: String, filter: ThemedReviewFilter = ThemedReviewFilter(), cardsPerSession: Int = 20,
         interval: ReviewInterval = .daily, orderMode: ReviewOrderMode = .dueFirst)
    init(_ review: ThemedReview) // copies the editable fields
}

enum ThemedReviewError: Error, Equatable, LocalizedError {
    case emptyName               // "Enter a name."
    case nameTooLong             // "Names can have at most 80 characters."
    case invalidCardsPerSession  // "Cards per session must be between 5 and 100."
    case invalidInterval         // "Choose an interval: every 1 to 365 days, or at least one weekday."
    case notFound                // "This themed review no longer exists."
}

struct ThemedQueueSnapshot: Sendable, Equatable {
    /// Not suspended cards whose highlight matches the filter (any state, due or not). Ordered cardId ASC.
    var candidates: [ReviewQueueEntry]
    /// Cards rated since dayStart in any session (ARCHITECTURE §10.2: excluded from the themed session).
    var ratedTodayCardIds: Set<String>
}

struct ThemedReviewRepository: Sendable {
    static let cardsPerSessionRange = 5...100
    static let maxNameLength = 80
    init(database: AppDatabase)

    /// Ordered by name (localized case-insensitive), then id; same order as ExportRepository.fetchThemedReviews.
    func fetchAll() async throws -> [ThemedReview]
    func observeAll() -> AsyncValueObservation<[ThemedReview]>
    func fetch(id: String) async throws -> ThemedReview?
    /// Validates (below), inserts with id UUID().uuidString, createdAt = date, lastCompletedAt nil.
    func create(_ draft: ThemedReviewDraft, at date: Date) async throws -> ThemedReview
    /// Validates; updates name, filter, cardsPerSession, interval, orderMode (columns). lastCompletedAt unchanged.
    func update(id: String, _ draft: ThemedReviewDraft) async throws
    /// Copy named "<name> copy" (cut to 80 characters), new id, createdAt = date, lastCompletedAt nil.
    func duplicate(id: String, at date: Date) async throws -> ThemedReview
    /// Review logs keep their rows (themedReviewId becomes NULL, schema FK). Returns false when missing.
    @discardableResult func delete(id: String) async throws -> Bool
    /// Sets lastCompletedAt (column-limited). Missing → .notFound.
    func markCompleted(id: String, at date: Date) async throws
    /// One read. The filter becomes a HighlightBrowserFilter (tagIds, tagMode, documentIds, categoryIds, colors; the
    /// same mapping as ExportRepository's themedReview scope) and HighlightBrowseSQL.conditions builds the WHERE part.
    func themedQueue(filter: ThemedReviewFilter, dayStart: Date) async throws -> ThemedQueueSnapshot
}
```
Validation (`create` and `update`): name trimmed, 1–80 characters (stored trimmed); `cardsPerSession` in 5…100 (no clamping, throw); interval `.everyNDays` needs `n` in 1…365; `.weekdays` needs at least one value, all in 1…7 (stored de-duplicated and sorted); `.daily` stores `n` and `weekdays` as nil. Filter ids are stored as given (deleted tags or documents simply match nothing).

## Acceptance criteria
Tests use an in-memory database, `TestData` records, cards from `ReviewCardFactory`, and end with `FTSIntegrity.check` when they write highlights.
1. `ThemedReviewRepositoryTests/createValidatesAndStores`: a valid draft round-trips (filter, interval, order); each invalid case throws its error (empty name, 81 characters, 4 and 101 cards, every 0 days, every 366 days, no weekdays, weekday 8) and inserts nothing; weekdays [6, 2, 2] are stored as [2, 6].
2. `ThemedReviewRepositoryTests/updateKeepsCompletion`: after `markCompleted`, `update` changes the fields and keeps `lastCompletedAt`; unknown id → `.notFound`.
3. `ThemedReviewRepositoryTests/duplicateAndDelete`: duplicate gets "<name> copy", a new id, nil `lastCompletedAt`; delete returns true, then false; a review log with that `themedReviewId` stays with NULL.
4. `ThemedReviewRepositoryTests/observeAllOrdersByName`: "b", "A", "c" → A, b, c; the observation emits after a create (`TestWait.until`).
5. `ThemedReviewRepositoryTests/themedQueueMatchesTheFilter` (table): tags any/all, documents, categories, colours, and an empty filter (= every non-suspended card); suspended cards and cards of non-matching highlights are left out; new and future cards are included.
6. `ThemedReviewRepositoryTests/ratedTodayIsReported`: logs before and after `dayStart` → only today's card ids.
7. Existing `ExportRepositoryTests` pass (the themed-review export scope is untouched).
8. `./scripts/test.sh StudyReaderTests/ThemedReviewRepositoryTests StudyReaderTests/ExportRepositoryTests StudyReaderTests/AppEnvironmentTests` passes; `./scripts/build.sh` succeeds.

## Out of scope
- Picking and ordering the session (T121), due logic (T121), export targets of a deleted themed review (BACKLOG B40, README Q8).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
