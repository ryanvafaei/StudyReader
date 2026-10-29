# T114: Mastery card writes

- **Phase:** 2 (E2.3 Mastery; SPEC F-16 AC2 data part)
- **Agent:** data-layer
- **Depends on:** T99
- **ADRs:** **ADR-0021** (suspension rule, cloze text in `answer`), ADR-0012
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 6.

## Goal
Insert, update and delete cloze and Q&A cards so the passive card is suspended while a highlight has Mastery cards and comes back when the last one is deleted, always in one transaction through `ReviewSuspension`.

## Files to touch
- `StudyReader/Core/Repositories/ReviewCardRepository.swift` (modify: three methods; two `ReviewCardError` cases)
- `StudyReaderTests/CoreTests/MasteryCardWriteTests.swift` (new)

## Interfaces to produce
```swift
enum ReviewCardError {           // add to the T99 enum
    case notMasteryCard          // "Only cloze and question cards can be changed here."
    case highlightMismatch       // "These cards belong to another highlight."
}

extension ReviewCardRepository {
    /// One transaction. Every card must be .cloze or .qa (else .notMasteryCard) with card.highlightId == highlightId
    /// (else .highlightMismatch); missing highlight → RepositoryError.notFound. Inserts each card with insert(db), then
    /// ReviewSuspension.recompute(highlightIds: [highlightId]) (the passive card becomes .mastery; the new cards get
    /// their suspension from the category). Nothing is written when any check fails.
    func insertMasteryCards(_ cards: [ReviewCard], highlightId: String) async throws

    /// Column-limited update of clozeRanges, question and answer (all three are written; pass the current value to keep
    /// one). FSRS state, dueAt and state are untouched (the card keeps its schedule). Missing → RepositoryError.notFound;
    /// a passive card → .notMasteryCard.
    func updateMasteryCard(id: String, clozeRanges: [[Int]]?, question: String?, answer: String?) async throws

    /// One transaction: delete the card (its review logs go with it through the cascade), then
    /// ReviewSuspension.recompute(highlightIds: [its highlightId]). A passive card → .notMasteryCard (nothing deleted).
    /// Returns false when no card had this id.
    @discardableResult
    func deleteMasteryCard(id: String) async throws -> Bool
}
```

## Acceptance criteria
Tests use an in-memory database, `TestData` records, cards from `ReviewCardFactory.passive`/`.mastery`, and end with `FTSIntegrity.check`.
1. `MasteryCardWriteTests/insertSuspendsPassive`: highlight with an active passive card; insert one cloze + one qa → passive `.mastery`, both new cards active.
2. `MasteryCardWriteTests/deleteLastRestoresPassive`: delete the qa → passive still `.mastery`; delete the cloze → passive active again (nil reason). With the category set to off before the last delete → passive `.frequencyOff`.
3. `MasteryCardWriteTests/insertChecks`: a passive card in the list → `.notMasteryCard`; a card of another highlight → `.highlightMismatch`; unknown highlight → `.notFound`; in each case no row was inserted.
4. `MasteryCardWriteTests/updateKeepsSchedule`: a cloze card rated once (use `recordRating`): `updateMasteryCard` with new ranges and answer → ranges and answer stored; `fsrsCard`, `dueAt`, `state`, `introducedAt` unchanged; its log still exists; passive card → `.notMasteryCard`; unknown id → `.notFound`.
5. `MasteryCardWriteTests/deleteRejectsPassive`: deleting the passive card throws `.notMasteryCard`; an unknown id returns false.
6. `./scripts/test.sh StudyReaderTests/MasteryCardWriteTests StudyReaderTests/ReviewCardRepositoryTests` passes; `./scripts/build.sh` succeeds.

## Out of scope
- Validation of ranges and texts and building the cards (T115). Browser counts (T116).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
