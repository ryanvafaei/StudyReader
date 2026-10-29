# T129: Passive cards for highlights made before Phase 2 (one-time backfill)

- **Phase:** 2 (E2.1; SPEC F-15 "every highlight gets a passive review card")
- **Agent:** data-layer
- **Depends on:** T100, T101. Runs right after T101 (README row 6a).
- **ADRs:** **ADR-0021**, ADR-0015 (the "done" flag is a per-Mac setting)
- **Visual check needed:** yes (Mac row below: the user's real library)
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 5.
- **Open question:** README Q2. Run this task only if the user answers yes; otherwise drop it.

## Goal
The user's real library already has highlights from Phase 1, made before cards existed. On the first launch of a build with this task, give each highlight that has no review card a passive card, with the same category rule as for new highlights (frequency not Off and "create cards automatically" on), once. New cards enter the review only through the new-per-day budget (default 5), so there is no flood.

## Files to touch
- `StudyReader/Core/Repositories/ReviewCardRepository.swift` (modify: one method)
- `StudyReader/Core/Support/SettingsStore.swift` (modify: one key)
- `StudyReader/Features/Extraction/LibraryMaintenance.swift` (modify: one method)
- `StudyReader/App/AppEnvironment.swift` (modify: call it once in `startBackgroundWork()`)
- `StudyReaderTests/ExtractionTests/LibraryMaintenanceTests.swift` (modify: two tests)

## Interfaces to produce
```swift
// ReviewCardRepository
/// One transaction. For every highlight with no review card (any type), builds a card with `makeCard(highlight)`
/// and inserts it through `insertAutomaticPassiveCard` (category rule and suspension included). Returns the number
/// inserted.
@discardableResult
func backfillPassiveCards(_ makeCard: @Sendable (Highlight) throws -> ReviewCard) async throws -> Int

// SettingsStore
var passiveCardBackfillDone: Bool    // "settings.passiveCardBackfillDone", default false

// LibraryMaintenance
/// Runs the backfill once per Mac: does nothing when settings.passiveCardBackfillDone; otherwise backfills with
/// ReviewCardFactory.passive(highlightId: h.id, now: h.createdAt) (due at the highlight's creation, so the oldest
/// highlights come first among new cards) and then sets the flag. On error the flag stays false (retry next launch).
func backfillPassiveCardsOnce(cards: ReviewCardRepository, settings: SettingsStore) async throws -> Int
```
- `AppEnvironment.startBackgroundWork()`: after the extraction re-queue, `let n = (try? await LibraryMaintenance(…).backfillPassiveCardsOnce(cards: reviewCardRepository, settings: settingsStore)) ?? 0` and log the count (`Log.files.info`, public count only).
- Each in-memory launch has fresh ephemeral settings (T84), so the backfill also runs on seeded in-memory libraries; T111's seeded cards already exist, so it inserts nothing there.

## Acceptance criteria
1. `LibraryMaintenanceTests/backfillCreatesPassiveCardsOnce` (in-memory environment, own `TestSettings.make()` store): three highlights (one with a qa card, one in a category with auto-create off, one plain) → returns 1; the plain highlight has a passive card due at its `createdAt`; the flag is set; a second call returns 0 without reading.
2. `LibraryMaintenanceTests/backfillHonoursOffCategories`: a highlight in an Off category gets no card.
3. Ends with `FTSIntegrity.check`; existing `LibraryMaintenanceTests` pass.
4. Reviewer: the backfill uses `insertAutomaticPassiveCard` (no second category rule).
5. `./scripts/test.sh StudyReaderTests/LibraryMaintenanceTests StudyReaderTests/SettingsStoreTests` passes; `./scripts/build.sh` succeeds.
6. Report "Visual check needed: yes" with this Mac row. **T129 Backfill** (Mac, real library, once): launch the new build; Review shows up to 5 new cards from the oldest highlights; quit and relaunch: no new cards appear (the flag holds).

## Out of scope
- A UI to rerun the backfill.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
