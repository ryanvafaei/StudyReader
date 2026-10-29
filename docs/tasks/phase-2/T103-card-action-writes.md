# T103: Card action writes: frequency override and edited highlight text

- **Phase:** 2 (E2.2 Daily review; SPEC F-18 "Edit highlight", "Change frequency")
- **Agent:** data-layer
- **Depends on:** T102
- **ADRs:** **ADR-0021** (suspension, reschedule), ADR-0012, ADR-0013 (`editedText` is FTS-indexed)
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 6.

## Goal
The two writes behind the review actions that change stored data: a card's frequency override (with the caller's rescheduled FSRS state and the suspension recomputed) and the highlight's edited display text (F-18: the original `text` is kept for re-anchoring).

## Files to touch
- `StudyReader/Core/Repositories/ReviewCardRepository.swift` (modify: one method, one value type)
- `StudyReader/Core/Repositories/HighlightRepository.swift` (modify: one method)
- `StudyReaderTests/CoreTests/ReviewCardActionWriteTests.swift` (new)

## Interfaces to produce
```swift
/// The FSRS state after a frequency change (ReviewScheduler.rescheduledDue, T105).
struct RescheduledCard: Sendable, Equatable {
    var fsrsCard: String     // StoredFSRSCard JSON with the new due
    var dueAt: Date          // == its due
}

extension ReviewCardRepository {
    /// One transaction: set frequencyOverride (nil clears it), and when `rescheduled` is non-nil also fsrsCard and dueAt,
    /// with update(db, columns:); then ReviewSuspension.recompute(highlightIds: [card.highlightId]). Missing card →
    /// RepositoryError.notFound.
    func updateFrequencyOverride(cardId: String, override: ReviewFrequency?, rescheduled: RescheduledCard?) async throws
}

extension HighlightRepository {   // add inside HighlightRepository.swift, next to updateNote
    /// SPEC F-18 "Edit highlight". `editedText` is stored as given, except: nil, whitespace-only, or equal to the
    /// highlight's `text` → nil (no edit). Updates editedText and updatedAt with the existing column-limited helper
    /// (`update(id:columns:)`, columns ["editedText", "updatedAt"]); the FTS update trigger re-indexes it.
    /// Missing row → RepositoryError.notFound.
    func updateEditedText(id: String, editedText: String?, at date: Date) async throws
}
```

## Acceptance criteria
Tests use an in-memory database and `TestData` records; they write highlights, so they end with `FTSIntegrity.check`.
1. `ReviewCardActionWriteTests/overrideOffSuspendsAsUser`: an active passive card in Lecture slides → `updateFrequencyOverride(.off, rescheduled: nil)` → `frequencyOverride == .off`, `suspendedReason == .user`; then `.high` → active; then nil → active (category high), override nil.
2. `ReviewCardActionWriteTests/overrideHighInOffCategoryUnsuspends`: Notes set to off, card `.frequencyOff` → override `.high` → active.
3. `ReviewCardActionWriteTests/rescheduledStateIsStored`: with a `RescheduledCard` the card's `fsrsCard` and `dueAt` change; with nil they are unchanged; unknown card → `.notFound`.
4. `ReviewCardActionWriteTests/editedTextRules`: "New wording" stored; then "  " → nil; then the original `text` → nil; `text`, `richText` and `anchor` never change; `updatedAt` = the given date; unknown id → `.notFound`.
5. `ReviewCardActionWriteTests/editedTextIsSearchable`: after `updateEditedText(…, "photosynthesis basics")`, `env.searchService` finds the highlight for `photosynthesis` (use an in-memory `AppEnvironment` and its `searchService`; check the API name in `SearchService.swift`).
6. `./scripts/test.sh StudyReaderTests/ReviewCardActionWriteTests StudyReaderTests/HighlightRepositoryTests` passes; `./scripts/build.sh` succeeds.

## Out of scope
- Computing the rescheduled state (T105). Rating (T102). Notes (already `NoteEditorModel`).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
