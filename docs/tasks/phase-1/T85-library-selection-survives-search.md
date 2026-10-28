# T85: The library selection survives a search

- **Phase:** 1 (end-of-phase backlog pass, `docs/BACKLOG.md` B22 (1), user decision 2026-10-28; SPEC F-01, F-12)
- **Agent:** ui-builder
- **Depends on:** T84 (runs after it; no shared files)
- **ADRs:** none
- **Visual check needed:** no (the UI test `GlobalSearchTests/testTypingAQueryShowsGroupedResultsAndClearingRestoresTheSelection` in T88 checks it)
- **UI tests:** none here (build and unit tests only). T88 adds the UI test and runs `LibraryOpenTests` again.

## Goal
While a search query is active, `RootView` shows `SearchResultsView` instead of `LibraryView`, so `LibraryView` is torn down and its `@State` selection is lost. When the user clears the search field, the grid comes back with nothing selected. Move the selection into `AppSession` so clearing the search returns to the same selected document. Sort and layout already persist in Settings. The filter is not part of this task.

## Files to touch
- `StudyReader/App/AppSession.swift` (modify: one property)
- `StudyReader/Features/Library/LibraryView.swift` (modify)
- `StudyReaderTests/AppTests/AppSessionTests.swift` (new)

## Interfaces to produce
```swift
// AppSession
/// The library's selected document id. Kept here, not in LibraryView, so it survives the search results replacing
/// the library (BACKLOG B22 1). LibraryView shows it only while the document is listed (`LibraryModel.existingSelection`).
var librarySelection: String?
```

## What to do
1. `AppSession`: add `var librarySelection: String?` (default nil) with the doc comment above. Nothing else changes in `AppSession`.
2. `LibraryView`: remove `@State private var selection: String?`. Every read and write uses `session.librarySelection` instead:
   - grid card tap: `session.librarySelection = item.id`;
   - tap on empty grid space: `session.librarySelection = nil`;
   - hidden "Clear Selection" button: `session.librarySelection = nil`;
   - `currentSelection`: `model.existingSelection(session.librarySelection)`;
   - `tableSelection` setter: `session.librarySelection = $0`.
   Update the type's doc comment ("Holds only view state (pending delete, sheets). The selection lives in `AppSession`.").
3. `delete(_:)`: when the deleted item's id equals `session.librarySelection`, set it to nil, so a deleted document doesn't come back as a stale id.
4. Keep everything else as it is, in particular the hidden Return/Escape buttons and their `.disabled(currentSelection == nil || session.isSearchFocused)` guard (standing rule in `docs/HANDOFF.md`: Return and Escape typed in the search field must not open or clear).
5. `AppSessionTests` (Swift Testing, `@MainActor`, `@Suite("AppSession")`): `AppSession(environment: try AppEnvironment.inMemory())`, as `RootModelTests` does. Don't add a new helper type.

## Acceptance criteria
1. `AppSessionTests/librarySelectionStartsEmptyAndKeepsItsValue`: a new session has `librarySelection == nil`; after setting `"d1"`, it reads `"d1"`; after setting nil, it reads nil.
2. Reviewer Grep: `LibraryView.swift` has no `@State private var selection`, and no remaining `selection =` assignment except through `session.librarySelection`.
3. Existing `LibraryModelTests`, `RootModelTests` and `AppSettingsTests` pass: `./scripts/test.sh StudyReaderTests/AppSessionTests StudyReaderTests/LibraryModelTests StudyReaderTests/RootModelTests`. `./scripts/build.sh` succeeds.
4. Behaviour (checked by T88's UI test, not run here): select the Lecture card, type a query, clear the field → the Lecture card is selected again (`isSelected`). Return in the empty search field still opens nothing (`LibraryOpenTests`, run by T88).

## Out of scope
Persisting the selection across launches, hoisting the library filter (it still resets after a search; recorded in BACKLOG B22 as undecided), any change to `SearchModel`, `RootView` or the search UI, any UI test (T88).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
