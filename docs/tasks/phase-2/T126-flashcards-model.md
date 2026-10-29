# T126: FlashcardsModel

- **Phase:** 2 (E2.5 Flashcards view; SPEC F-17 AC2, F-18 "in the flashcards view")
- **Agent:** review-engine
- **Depends on:** T125, T105, T115
- **ADRs:** **ADR-0022** (no rating or Skip in the flashcards view, README Q3)
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 7.

## Goal
The logic behind the Flashcards view: the live, filtered card list, the selected card's preview, and the card actions that make sense outside a session (frequency, edit highlight text, open in document, edit Mastery cards). Rating and Skip stay in sessions.

## Files to touch
- `StudyReader/Features/Review/Flashcards/FlashcardsModel.swift` (new)
- `StudyReaderTests/ReviewTests/FlashcardsModelTests.swift` (new)

## Interfaces to produce
```swift
@MainActor @Observable
final class FlashcardsModel {
    init(environment: AppEnvironment, calendar: Calendar = .current)
    var filter = FlashcardFilter()                   // the view restarts observe() with .task(id: model.filter)
    var selection: String?                           // card id
    private(set) var items: [FlashcardItem] = []
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    // filter-menu lookups, live (same pattern as HighlightsBrowserModel.observeLookups)
    private(set) var documents: [LibraryDocument] = []
    private(set) var categories: [DocumentCategory] = []
    private(set) var tags: [LibraryTag] = []

    var selectedItem: FlashcardItem? { get }
    var selectedContent: ReviewCardContent? { get }  // ReviewCardContent.make(selectedItem.item, showOriginal:)
    var showOriginal = false
    var isFiltered: Bool { get }
    nonisolated static func countText(_ count: Int) -> String   // "1 card" / "N cards" (plural catalog entry)

    func observe() async                             // observeFlashcards(filter:) until cancelled; prunes a vanished selection
    func observeLookups() async
    func clearFilters()
    func toggle(state: FlashcardState)
    func toggle(cardType: CardType)
    func toggle(documentId: String)
    func toggle(categoryId: String)
    func toggle(tagId: String)
    var dueFromDay: Date? { get set }                // start of day, like HighlightsBrowserModel.fromDay
    var dueToDay: Date? { get set }                  // inclusive last day → dueBefore = next day start
    func setFrequency(_ override: ReviewFrequency?) async      // ReviewService.setFrequencyOverride on the selection
    func editHighlightText(_ text: String?) async               // ReviewService.editHighlightText
    /// Highlight id for the Mastery editor (T117 sheet); nil when nothing is selected.
    var masteryHighlightId: String? { get }
}
```
- Errors: "The cards couldn't be loaded.", "The frequency couldn't be changed.", "The highlight couldn't be changed.".
- A stale-run guard like T90's: `observe()` keeps a generation counter and drops values from a run that a newer run has replaced (BACKLOG follow-up on `HighlightsBrowserModel.observe`), so a fast filter change can't show the older filter's rows.

## Acceptance criteria
`@MainActor`, in-memory environment on `FixedNow(r)`, cards through repositories, end with `FTSIntegrity.check`. Use bounded waits (`TestWait.until` + `#expect`).
1. `FlashcardsModelTests/filtersByState`: new, learning, review and suspended cards → toggling each state narrows the list; toggling two ORs them.
2. `FlashcardsModelTests/filtersByDueDate`: `dueFromDay`/`dueToDay` map to the filter bounds (start of day, next day start) and narrow the list.
3. `FlashcardsModelTests/filtersCombine`: document + tag + state + type at once; `clearFilters()` restores all; `isFiltered` follows.
4. `FlashcardsModelTests/editsCards` (SPEC F-17 AC2 "edits cards"): `setFrequency(.off)` on the selection → the row's state becomes `.suspended`; `editHighlightText("New")` → the selected content shows "New" and `isEdited`; saving a changed Q&A through `MasteryService.save` updates the row's preview.
5. `FlashcardsModelTests/selectionIsPrunedAndCountText`: deleting the selected card's highlight clears `selection`; `countText(1) == "1 card"`, `countText(3) == "3 cards"`.
6. `FlashcardsModelTests/staleRunIsIgnored`: change the filter twice quickly; the final `items` match the last filter.
7. `./scripts/test.sh StudyReaderTests/FlashcardsModelTests` passes; `./scripts/build.sh` succeeds.

## Out of scope
- The view (T127). Rating in this view (README Q3).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
- 2026-10-29, implementer review-engine haiku medium (reworks: none), reviewer code-reviewer sonnet medium: APPROVED, spec met (masteryHighlightId is a settable stored var instead of get-only: accepted, same sheet-target pattern as HighlightsBrowserModel); CI build and full unit tests green, 940 tests (runs 40959352242, 40959903928)
