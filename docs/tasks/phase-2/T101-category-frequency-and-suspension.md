# T101: Category frequency and auto-create writes; suspension follows category changes

- **Phase:** 2 (E2.1 Scheduler; SPEC F-19 AC2, F-17 per-category setting, F-22 Review tab data)
- **Agent:** data-layer
- **Depends on:** T99
- **ADRs:** **ADR-0021** (suspension is recomputed on every change that can affect it), ADR-0012, ADR-0013
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 7.

## Goal
Settings > Review (T106) changes a category's frequency and its "create cards automatically" flag. Off suspends that category's cards at once, back on unsuspends them (F-19). Moving a document to another category, and deleting a category (its documents move to Other), recompute the cards of the moved documents.

## Files to touch
- `StudyReader/Core/Repositories/CategoryRepository.swift` (modify: two methods, `delete`)
- `StudyReader/Core/Repositories/DocumentRepository.swift` (modify: `updateMetadata`)
- `StudyReaderTests/ReviewTests/FrequencyPolicySuspensionTests.swift` (new: `extension FrequencyPolicyTests`, so the SPEC name `FrequencyPolicyTests/offSuspends` holds)
- `StudyReaderTests/CoreTests/CategoryRepositoryTests.swift`, `StudyReaderTests/CoreTests/DocumentRepositoryTests.swift` (modify: add tests)

## Interfaces to produce
```swift
// CategoryRepository (built-in and custom categories alike)
/// One transaction: update `frequency` (update(db, columns: ["frequency"])), then ReviewSuspension.recompute(categoryId:).
/// Missing category: CategoryError.notFound. Returns the number of cards whose suspension changed.
@discardableResult
func setFrequency(id: String, _ frequency: ReviewFrequency) async throws -> Int
/// update(db, columns: ["autoCreateCards"]). Existing cards are untouched. Missing: CategoryError.notFound.
func setAutoCreateCards(id: String, _ enabled: Bool) async throws
```
- `CategoryRepository.delete(id:)`: in the same transaction, collect the ids of the documents it moves to `BuiltinCategory.other` before the `updateAll`, then `ReviewSuspension.recompute(documentIds: movedIds, db)` after it. Return value unchanged (documents moved).
- `DocumentRepository.updateMetadata(id:title:author:categoryId:)`: when `categoryId` differs from the stored one, call `ReviewSuspension.recompute(documentIds: [id], db)` in the same write. The private `update(id:columns:_:)` helper takes a closure; the simplest way is a dedicated `writer.write` in `updateMetadata` that fetches, compares, updates the three columns and recomputes. Keep the title/author trimming and `DocumentEditError.emptyTitle` exactly as they are.

## Acceptance criteria
Tests use an in-memory database, `TestData.document`/`TestData.highlight`, cards from `ReviewCardFactory`, and end with `FTSIntegrity.check`.
1. `FrequencyPolicyTests/offSuspends` (SPEC F-19 AC2): in Paper (normal) a document with highlights A (passive), B (passive with override `.high`), C (passive with override `.off`, `.user`), D (passive + cloze: passive `.mastery`). `setFrequency(paper, .off)` → A `.frequencyOff`, B active, C `.user`, D passive `.mastery`, D cloze `.frequencyOff`. `setFrequency(paper, .normal)` → A active, B active, C `.user`, D passive `.mastery`, D cloze active. Prepare the starting state with `ReviewSuspension.recompute` after direct inserts.
2. `FrequencyPolicyTests/offAppliesToBuiltinAndCustomCategories`: the same for Lecture slides and a custom category; the return value counts changed cards; a document in another category is untouched.
3. `CategoryRepositoryTests/frequencyAndAutoCreatePersist`: both setters persist (fetch again); unknown id → `.notFound` for both; `setAutoCreateCards(false)` leaves existing cards unchanged.
4. `CategoryRepositoryTests/deleteRecomputesSuspension`: a custom category set to off with one document and one suspended card; deleting the category moves the document to Other (normal) and the card becomes active.
5. `DocumentRepositoryTests/categoryChangeRecomputesSuspension`: document in Lecture slides with an active card; Notes set to off; `updateMetadata` with the Notes category → card `.frequencyOff`; back to Lecture slides → active; an update that keeps the category changes no card (`suspended`/`suspendedReason` unchanged, title still updates).
6. Existing `CategoryRepositoryTests` and `DocumentRepositoryTests` pass unchanged (incl. `metadataUpdate`).
7. `./scripts/test.sh StudyReaderTests/FrequencyPolicyTests StudyReaderTests/CategoryRepositoryTests StudyReaderTests/DocumentRepositoryTests` passes; `./scripts/build.sh` succeeds.

## Out of scope
- The Settings UI (T106). Card frequency overrides (T103).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
