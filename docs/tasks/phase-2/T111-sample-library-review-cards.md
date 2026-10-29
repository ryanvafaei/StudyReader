# T111: Sample library seeds review cards

- **Phase:** 2 (E2.2; test data for T112 and checkpoint R1)
- **Agent:** ui-builder
- **Depends on:** T99 (`insertPassiveCards`), T105 (the test builds the plan with `ReviewService`)
- **ADRs:** ADR-0019 (UI tests seed with Debug > Seed Sample Library), **ADR-0021**
- **Visual check needed:** no
- **UI tests:** none in this task. Verify with `./scripts/build.sh` and the filter in criterion 4.

## Goal
Debug > Seed Sample Library also gives every seeded highlight a passive review card in a fixed state, so a fresh in-memory launch has a known daily review: 4 due and 4 new cards (8 in the session with the default limits) and 2 cards due later.

## Files to touch
- `StudyReader/Features/Debug/SampleLibrary.swift` (modify)
- `StudyReaderTests/LibraryTests/SampleLibraryTests.swift` (modify: one test)

## What to do
1. Add to `SampleHighlight` a `review: SampleReview` with default `.new`:
   ```swift
   private enum SampleReview: Sendable {
       case new                       // ReviewCardFactory.passive(highlightId:now: createdAt)
       case due(hoursAgo: Double)     // review-state card due `hoursAgo` hours before seeding time
       case later(days: Double)       // review-state card due `days` days after seeding time
   }
   ```
2. Set these states (seeding order index in brackets, as in the existing creation-time spread):
   - Lecture 1 p. 1 yellow [0]: `.due(hoursAgo: 48)`; p. 2 green with note [1]: `.due(hoursAgo: 24)`; p. 3 blue [2]: `.new`.
   - Gradient Descent "lowers the loss" [3]: `.due(hoursAgo: 72)`; "too large a step can diverge" [4]: `.new`; "small batch of examples" [5]: `.new`; "running average" [6]: `.later(days: 5)`.
   - Probability [7]: `.due(hoursAgo: 1)`. Pendulum [8]: `.later(days: 10)`. Membrane Transport [9]: `.new`.
3. After each sample's highlights are inserted, build one card per highlight and insert them with `environment.reviewCardRepository.insertPassiveCards(_:)` (one call per sample):
   - `.new`: `ReviewCardFactory.passive(highlightId:now:)` with the highlight's `createdAt`.
   - `.due`/`.later`: the factory card, with `fsrsCard` replaced by `StoredFSRSCard(due: d, stability: 5, difficulty: 5, scheduledDays: 5, reps: 2, state: .review, lastReview: d − 5 days).json()` and `dueAt = d`, `state = .review`, where `d = (now ± offset).storageRounded`.
   Nothing here issues SQL (the file's rule); the seeding stays idempotent (existing samples are skipped as before, cards come with their highlights).
4. Expected daily session with the default limits (15/5): due first by due date — "lowers the loss", Lecture p. 1, Lecture p. 2 ("Cristae increase the inner membrane surface area.", note "Check this for the quiz"), Probability; then new by oldest highlight — Membrane Transport, "small batch of examples", "too large a step can diverge", Lecture p. 3. Write this order in a comment above the sample definitions; T112 relies on it.

## Acceptance criteria
1. `SampleLibraryTests/seededReviewCardsGiveAKnownDailyPlan` (in-memory environment with `FixedNow(r)`): after `seed()`, `reviewCardRepository` has 10 cards (one per highlight); `ReviewService(…, calendar: utc).dailyPlan(limits: .defaults)` gives 8 ids whose highlights' texts are, in order, the eight listed in step 4; `dueCount == 4`, `newCount == 4`. A second `seed()` adds no card.
2. Existing `SampleLibraryTests` pass unchanged (distinct creation times, position keys, Markdown anchors, removal deletes the cards with the highlights through the cascade).
3. Reviewer: no SQL in `SampleLibrary.swift`; still `#if DEBUG` only.
4. `./scripts/test.sh StudyReaderTests/SampleLibraryTests` passes; `./scripts/build.sh` succeeds.

## Out of scope
- Seeding Mastery cards or themed reviews (T128 creates them through the UI).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
- 2026-10-29, implementer ui-builder sonnet medium (reworks: none), reviewer code-reviewer sonnet medium: APPROVED, spec met, expected plan order re-derived by hand; CI build and full unit tests green, 867 tests (runs 40911148916, 40911541531)
