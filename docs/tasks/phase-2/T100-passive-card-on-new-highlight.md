# T100: New highlights get a passive review card

- **Phase:** 2 (E2.1 Scheduler; SPEC F-15 "every highlight gets a passive review card when created", F-17 AC1)
- **Agent:** data-layer
- **Depends on:** T99
- **ADRs:** **ADR-0021**, ADR-0012
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 6.

## Goal
Every highlight created through `HighlightService` (text and snapshot, PDF and Markdown) gets a passive review card in the same transaction as the highlight, when its category allows it (`frequency != off` and `autoCreateCards`).

## Files to touch
- `StudyReader/Core/Repositories/HighlightRepository.swift` (modify: `insert`)
- `StudyReader/Features/Annotations/HighlightService.swift` (modify: `createText`, `createImage`)
- `StudyReaderTests/ReviewTests/CardCreationTests.swift` (new)

## Interfaces to produce
```swift
// HighlightRepository
/// One transaction: the highlight, one HighlightTag per distinct tag id, then, when `passiveCard` is given,
/// `ReviewCardRepository.insertAutomaticPassiveCard(passiveCard, db)` (which checks the category itself).
func insert(_ highlight: Highlight, tagIds: [String] = [], passiveCard: ReviewCard? = nil) async throws
```
- `HighlightService.createText` and `createImage`: build `let card = try ReviewCardFactory.passive(highlightId: highlight.id, now: date)` with the same `date` as the highlight's `createdAt`, and pass it as `passiveCard`. If the factory throws, the highlight isn't created (the error propagates, like any insert error; `createImage` still deletes its PNG).
- Everything else in `HighlightService` (undo mark, errors) stays as it is. `undoAutoHighlight` → `deleteIfUnannotated` removes the card through the SQL cascade (no change needed; criterion 4 checks it).
- `SampleLibrary` and other direct `highlightRepository.insert(…)` callers keep calling without `passiveCard` (T111 seeds cards for samples).

## Acceptance criteria
Tests use an in-memory `AppEnvironment` (`defer { TestFileStore.remove(env.fileStore) }`), a document from `TestData.document` inserted with `documentRepository.insert`, `NewTextHighlight`/`NewImageHighlight` values, and end with `FTSIntegrity.check`. Change a category's columns in tests with a fetched `DocumentCategory` and `update(db, columns:)`.
1. `CardCreationTests/respectsCategorySetting` (SPEC F-17 AC1, table over categories): Lecture slides (high, auto on) → one passive card, not suspended; Notes with `autoCreateCards = false` → no card; Paper with frequency off → no card; Other (normal, auto on) → one card.
2. `CardCreationTests/newCardIsNewAndDueAtCreation`: the card's `state == .new`, `dueAt == highlight.createdAt`, `introducedAt == nil`, `StoredFSRSCard(json: card.fsrsCard) == .new(due: highlight.createdAt)`.
3. `CardCreationTests/imageHighlightGetsACard`: `createImage` with a 1×1 PNG → one passive card.
4. `CardCreationTests/undoRemovesTheCard`: `createText(isAuto: true)`, then `undoAutoHighlight(id:)` → no `reviewCard` rows left.
5. Existing `HighlightServiceTests` and `HighlightRepositoryTests` pass unchanged.
6. `./scripts/test.sh StudyReaderTests/CardCreationTests StudyReaderTests/HighlightServiceTests StudyReaderTests/HighlightRepositoryTests` passes; `./scripts/build.sh` succeeds.

## Out of scope
- Cards for highlights created before Phase 2 (T129, only if the user agrees, README Q2).
- Category writes (T101).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
- 2026-10-29, implementer data-layer haiku medium (reworks: none), reviewer code-reviewer sonnet medium: APPROVED, spec met; CI build and full unit tests green (runs 40869709228, 40870076783)
