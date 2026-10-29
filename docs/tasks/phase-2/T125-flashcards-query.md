# T125: Flashcards query

- **Phase:** 2 (E2.5 Flashcards view; SPEC F-17 "browse all cards with filters (document, tag, category, state New/Learning/Review/Suspended, due date)")
- **Agent:** data-layer
- **Depends on:** T114
- **ADRs:** ADR-0012 (dates as `.databaseUnixSeconds`)
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 6.

## Goal
One query (and its live version) over every review card, passive and Mastery, with the F-17 filters, returning what the Flashcards view lists.

## Files to touch
- `StudyReader/Core/Repositories/FlashcardQuery.swift` (new: types and `enum FlashcardSQL`)
- `StudyReader/Core/Repositories/ReviewCardRepository.swift` (modify: two thin methods)
- `StudyReaderTests/CoreTests/FlashcardQueryTests.swift` (new)

## Interfaces to produce
```swift
/// SPEC F-17 card states. learning covers FSRS learning and relearning; suspended wins over the FSRS state.
enum FlashcardState: String, Sendable, CaseIterable {
    case new, learning, review, suspended
}

struct FlashcardFilter: Sendable, Equatable {
    var documentIds: Set<String> = []
    var categoryIds: Set<String> = []
    var tagIds: Set<String> = []
    var tagMode: TagMatchMode = .any
    var states: Set<FlashcardState> = []      // empty = all
    var cardTypes: Set<CardType> = []         // empty = all
    var dueFrom: Date? = nil                  // dueAt >= dueFrom
    var dueBefore: Date? = nil                // dueAt < dueBefore
}

struct FlashcardItem: Sendable, Equatable, Identifiable {
    var item: ReviewCardItem                  // T102 type (card, highlight, title, category frequency, tags)
    var state: FlashcardState
    var lastReviewedAt: Date?
    var id: String { item.id }
}

extension ReviewCardRepository {
    /// Ordered dueAt ASC, then card id. Highlight-side filters reuse HighlightBrowseSQL.conditions (documents,
    /// categories, tags with mode) on the card's highlight; states, types and due dates filter the card.
    func flashcards(filter: FlashcardFilter) async throws -> [FlashcardItem]
    func observeFlashcards(filter: FlashcardFilter) -> AsyncValueObservation<[FlashcardItem]>
}
```
- State filter SQL: suspended → `r.suspended = 1`; new → `r.suspended = 0 AND r.state = 'new'`; learning → `r.suspended = 0 AND r.state IN ('learning','relearning')`; review → `r.suspended = 0 AND r.state = 'review'`; several states OR together inside one parenthesis.
- Tag names for all rows in one extra query (as T102 `items(cardIds:)` does).

## Acceptance criteria
In-memory database, `TestData` records, cards inserted with explicit states/suspension/dueAt, end with `FTSIntegrity.check`.
1. `FlashcardQueryTests/statesMapAsSpecified`: one card each: new, learning, relearning, review, suspended review → `.new`, `.learning`, `.learning`, `.review`, `.suspended`; filter `[.learning]` → two rows; `[.new, .suspended]` → two rows.
2. `FlashcardQueryTests/highlightFiltersCombine`: document, category and tag (any/all) filters, each alone and all three together.
3. `FlashcardQueryTests/dueRangeAndTypes`: `dueFrom`/`dueBefore` inclusive/exclusive as documented; `cardTypes [.cloze, .qa]` → only Mastery cards.
4. `FlashcardQueryTests/orderAndLastReview`: rows by dueAt then id; `lastReviewedAt` is the latest log time.
5. `FlashcardQueryTests/observeEmitsOnChange`: after `updateFrequencyOverride(.off)` a row moves to `.suspended` (`TestWait.until`, `#expect`).
6. `./scripts/test.sh StudyReaderTests/FlashcardQueryTests StudyReaderTests/ReviewQueueTests` passes; `./scripts/build.sh` succeeds.

## Out of scope
- The model and the view (T126, T127).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
