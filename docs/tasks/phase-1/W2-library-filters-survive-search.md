# W2: The library filters survive a search

- **Phase:** 1 (wrap-up, user decision 2026-10-29; `docs/BACKLOG.md` B22 "library filter"; SPEC F-01, F-12)
- **Agent:** ui-builder
- **Depends on:** W1 (order only; no shared files), T85 (same pattern)
- **ADRs:** none
- **Visual check needed:** yes (Mac row below; the orchestrator adds it to VISUAL_CHECKS.md "Needs a Mac" from your report)
- **UI tests:** none. Verify with `./scripts/build.sh` and the unit-test filter in acceptance criterion 5 only. No XCUITest touches the library Filter menu (Grep for "Filter documents", "Has Highlights", "Clear Filters" in `StudyReaderUITests/` finds nothing). The filter starts empty on every launch, so `GlobalSearchTests` and `LibraryOpenTests` see the same state as before. No UI run is needed after this task.

## Goal
"Filters" here means `LibraryFilter` in `LibraryModel.swift`: `categoryId`, `tagId`, `fileType` and `hasHighlightsOnly`. The toolbar's Filter menu in `LibraryView` sets them through Category, Tag, File Type and Has Highlights, with Clear Filters at the end.

Today they reset after a global search:
- `LibraryView` owns `@State private var model: LibraryModel`, created in its `init` with `LibraryModel(environment:)`, so `filter` starts as `LibraryFilter()`.
- While a query is active, `RootView`'s detail shows `SearchResultsView` instead of `LibraryView` (`if search.isActive`). `LibraryView` and its `@State` model are torn down.
- Clearing the field creates a new `LibraryView` with a new model and an empty filter.
- Switching the sidebar to Tags or Categories and back does the same.

This is the same cause T85 fixed for the selection. Fix it the same way: keep the filter in `AppSession` (`session.libraryFilter`), and give each new `LibraryModel` the session's filter and a way to write it back. Sort and layout already persist in Settings and don't change.

You may touch other files if needed; say so in the report, with the reason.

## Files to touch
- `StudyReader/App/AppSession.swift` (modify: one property)
- `StudyReader/Features/Library/LibraryModel.swift` (modify: initializer, `filter` write-back, stale ids)
- `StudyReader/Features/Library/LibraryView.swift` (modify: one line in `init`, doc comment)
- `StudyReaderTests/LibraryTests/LibraryModelTests.swift` (modify: two tests)

## Interfaces to produce
```swift
// AppSession
/// The library's filter (category, tag, file type, has highlights). Kept here, not in LibraryView's model, so it
/// survives the search results replacing the library and a switch to another sidebar section (W2, BACKLOG B22).
/// Not persisted across launches.
var libraryFilter = LibraryFilter()

// LibraryModel
/// `filter` starts as the given value; every later change is passed to `onFilterChange` (W2).
init(
    environment: AppEnvironment,
    filter: LibraryFilter = LibraryFilter(),
    onFilterChange: @escaping @MainActor (LibraryFilter) -> Void = { _ in }
)

/// The model LibraryView uses: starts with `session.libraryFilter` and writes every filter change back to it.
convenience init(session: AppSession)

var filter: LibraryFilter   // didSet: if filter != oldValue { onFilterChange(filter) }
```

## What to do
1. **`AppSession`:** add `var libraryFilter = LibraryFilter()` with the doc comment above, next to `librarySelection`. Nothing else changes.
2. **`LibraryModel`:**
   - Replace `var filter = LibraryFilter()` with a stored `var filter: LibraryFilter` that has a `didSet` calling `onFilterChange(filter)` when `filter != oldValue`. `sort` and `layout` already use `didSet` in this `@Observable` class.
   - Store the closure as `@ObservationIgnored private let onFilterChange: @MainActor (LibraryFilter) -> Void`.
   - The designated `init(environment:filter:onFilterChange:)` sets `self.filter = filter` (no `didSet` runs in `init`, so creating a model writes nothing back). The defaults keep every existing `LibraryModel(environment:)` call compiling and behaving as before.
   - `convenience init(session: AppSession)`: `self.init(environment: session.environment, filter: session.libraryFilter, onFilterChange: { session.libraryFilter = $0 })`. Capturing `session` strongly is fine: `AppSession` never holds a `LibraryModel`, so there is no cycle.
   - **Stale ids:** the kept filter may name a tag or category deleted while the library was hidden (Tags/Categories sections, merges). In `observeTags()`, right after `tags = observed`: if `filter.tagId` is set and `observed` has no tag with that id, set `filter.tagId = nil`. In `observeCategories()`, the same for `filter.categoryId` against `observed` categories. The `didSet` writes the result back to the session. Only an observed list is checked; before its first emission nothing is dropped. `fileType` and `hasHighlightsOnly` are never dropped.
3. **`LibraryView`:** in `init`, `_model = State(initialValue: LibraryModel(session: session))`. Update the type's doc comment: "The selection and the filter live in `AppSession`."
   - Nothing else changes in `LibraryView`. The menu bindings (`$model.filter.categoryId`, `.tagId`, `.fileType`, `.hasHighlightsOnly`) and both Clear Filters buttons (`model.filter = LibraryFilter()`, in the toolbar menu and in the "No documents match these filters" state) already write through `filter`, so they reach the session.
   - Keep the hidden Return/Escape buttons and their `.disabled(currentSelection == nil || session.isSearchFocused)` guard as they are.
4. **Clear Filters** resets all four fields in the model and in `session.libraryFilter`. It doesn't touch the selection, the sort, the layout or the search.
5. **Separate from the search filters.** `SearchModel.filters` (`SearchFilters`: tag, category and file type in the search results' filter bar, T66) is a different filter and stays separate. The library filter doesn't seed the search filters, and the search filters don't change the library filter. Don't change `SearchModel`, `SearchResultsView` or `RootView`.

**Constraint (HANDOFF standing rule, Library Return/Escape):** not triggered. This task adds no text or search field to the main window.

## Acceptance criteria
1. `LibraryModelTests/filterSurvivesANewModelForTheSameSession` (synchronous, no observation). Steps:
   - Create `let session = AppSession(environment: try AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate)))` and `defer { TestFileStore.remove(session.environment.fileStore) }`. Check `session.libraryFilter == LibraryFilter()`.
   - `let first = LibraryModel(session: session)`. Set the four fields one at a time, as the menu bindings do: `first.filter.categoryId = "c1"`, `first.filter.tagId = "t1"`, `first.filter.fileType = .markdown`, `first.filter.hasHighlightsOnly = true`.
   - Check `session.libraryFilter == LibraryFilter(categoryId: "c1", tagId: "t1", fileType: .markdown, hasHighlightsOnly: true)` and `session.search.filters == SearchFilters()` (the search filters are untouched).
   - `let second = LibraryModel(session: session)` (LibraryView created again after the search): `second.filter` equals the same value.
   - `second.filter = LibraryFilter()` (Clear Filters): `session.libraryFilter == LibraryFilter()`.
   - `let third = LibraryModel(session: session)`: `third.filter == LibraryFilter()` and `!third.filter.isActive`.
   - `LibraryModel(environment: session.environment)` still starts with `LibraryFilter()`, and changing its filter leaves `session.libraryFilter` unchanged.
2. `LibraryModelTests/filterDropsADeletedTagOrCategory` (`.timeLimit(.minutes(1))`, uses the suite's existing private `waitUntil`). Steps:
   - Use an in-memory session as above, with `let env = session.environment`.
   - Create `let tag = try await env.tagRepository.findOrCreate(name: "exam", at: TestData.referenceDate)` and `let category = try await env.categoryRepository.create(name: "Seminar")`.
   - `let model = LibraryModel(session: session)`; start `observeTags()` and `observeCategories()` in two `Task`s. Wait until both lists contain the new ids.
   - Set `model.filter.tagId = tag.id`, `model.filter.categoryId = category.id`, `model.filter.hasHighlightsOnly = true`.
   - `try await env.tagRepository.delete(id: tag.id)`, then wait until `model.filter.tagId == nil`.
   - `_ = try await env.categoryRepository.delete(id: category.id)`, then wait until `model.filter.categoryId == nil`.
   - Check `model.filter == LibraryFilter(hasHighlightsOnly: true)` and `session.libraryFilter == LibraryFilter(hasHighlightsOnly: true)`.
   - Cancel both tasks and await them.
   - No FTS-indexed table is written, so no `FTSIntegrity.check` is needed.
3. Reviewer Grep: `LibraryView.swift` creates the model only with `LibraryModel(session: session)`. `LibraryModel.swift` has no `var filter = LibraryFilter()`. No new `LibraryFilter()` assignment was added outside the two existing Clear Filters buttons.
4. Existing `LibraryModelTests` (sort, filter, `sortAndLayoutPersist`, observation tests), `AppSessionTests` and `RootModelTests` pass unchanged.
5. `./scripts/test.sh StudyReaderTests/LibraryModelTests StudyReaderTests/AppSessionTests StudyReaderTests/RootModelTests` passes; `./scripts/build.sh` succeeds.
6. Report "Visual check needed: yes" with this Mac row for VISUAL_CHECKS.md "Needs a Mac". **W2 library filters survive a search:**
   1. In the library, choose Filter > Category > Lecture slides and turn on Filter > Has Highlights. Note which documents show.
   2. Type a word in the search field (the search results replace the library), then clear the field. The library shows the same filtered documents, and the Filter menu still shows Lecture slides and Has Highlights checked.
   3. Switch the sidebar to Tags and back to Library: the filter is still on.
   4. Choose Filter > Clear Filters: all documents show. Type and clear a search again: still all documents.
   5. Set a tag filter, delete that tag in Tags, return to Library: the tag filter is gone and the other filters stay.
   6. Quit and relaunch: the filter starts empty (not persisted, by design).

## Out of scope
- Persisting the filter across launches (SettingsStore). That is out of scope by decision: the user asked only for search survival.
- Any change to `SearchModel`, `SearchFilters`, `SearchResultsView` or `RootView`.
- Moving the whole `LibraryModel` into `AppSession`.
- The library sort or layout (already persisted).
- Any UI test.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
