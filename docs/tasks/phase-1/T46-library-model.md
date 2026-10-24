# T46: LibraryModel (sort, filter, live list)

- **Phase:** 1 (E1.1: F-01)
- **Agent:** ui-builder
- **Depends on:** T33, T34, T44 (`extractionService`)
- **ADRs:** ARCHITECTURE §3 (models), docs/decisions/0015-settings-and-injected-sleep.md
- **Visual check needed:** no (T47 shows it)

## Goal
The logic behind the library screen: observe `LibraryItem`s, apply SPEC F-01 sorts and filters, persist layout and sort, delete documents. Pure static sort/filter functions make the AC tests simple.

## Files to touch
- `StudyReader/Features/Library/LibraryModel.swift` (new)
- `StudyReaderTests/LibraryTests/LibraryModelTests.swift` (new)

## Interfaces to produce
```swift
struct LibraryFilter: Sendable, Equatable {
    var categoryId: String? = nil
    var tagId: String? = nil
    var fileType: FileType? = nil
    var hasHighlightsOnly: Bool = false
    var isActive: Bool { get }          // any field set
}

@MainActor @Observable
final class LibraryModel {
    init(environment: AppEnvironment)
    private(set) var items: [LibraryItem] = []          // latest observed, unsorted order from the repository
    var visibleItems: [LibraryItem] { get }             // Self.filtered then Self.sorted
    var sort: LibrarySort { didSet { environment.settingsStore.librarySort = sort } }      // initial value from the store
    var layout: LibraryLayout { didSet { environment.settingsStore.libraryLayout = layout } }
    var filter = LibraryFilter()
    private(set) var errorMessage: String?

    /// Runs documentRepository.observeItems() until the calling task is cancelled (`.task {}` in the view).
    func observe() async
    func delete(documentId: String) async        // documentRepository.delete(id:fileStore:); errors → errorMessage
    func retryExtraction(documentId: String) async   // environment.extractionService.enqueue

    nonisolated static func sorted(_ items: [LibraryItem], by sort: LibrarySort) -> [LibraryItem]
    nonisolated static func filtered(_ items: [LibraryItem], by filter: LibraryFilter) -> [LibraryItem]
}
```
Sort rules (ties always end with `id` ascending so order is total):
- `.dateAdded`: `addedAt` descending.
- `.lastOpened`: `lastOpenedAt` descending; never-opened documents last, among them `addedAt` descending.
- `.title`: `title.localizedStandardCompare` ascending.
- `.author`: `author.localizedStandardCompare` ascending; empty authors last; ties by title.

Filter rules (all set fields must match): category equals; `tagIds` contains `tagId`; file type equals; `hasHighlightsOnly` → `highlightCount > 0`.

## Tests (`LibraryModelTests`)
Static tests use hand-built `LibraryItem`s (`TestData.document` + fields):
- `sortDateAdded`, `sortLastOpened` (includes two never-opened), `sortTitle` (includes "Lecture 2" vs "Lecture 10" → 2 first), `sortAuthor` (includes an empty author → last).
- `filterCategory`, `filterTag`, `filterFileType`, `filterHasHighlights`, `filtersCombine` (category + file type + has highlights).
Model tests (`@MainActor`):
- `listsPersistedDocuments` (SPEC F-01 AC1): `TestFileStore.make()` (+ remove); `AppEnvironment.make(fileStore:)`; insert two documents (one with a highlight); drop it; a second `AppEnvironment.make(fileStore:)` → `LibraryModel`; run `observe()` in a `Task`, poll (bounded, `.timeLimit(.minutes(1))`) until `items.count == 2`; fields (title, author, categoryName, highlightCount, progress, lastOpenedAt) match; cancel the task.
- `sortAndLayoutPersist`: set `sort = .title`, `layout = .list` on a model over `inMemory()` with a `TestSettings` store passed to `AppEnvironment(fileStore:database:now:settingsStore:)`; a new model over the same store starts with `.title` and `.list`.
- `deleteRemovesItem`: delete via the model; the observed list drops it; its folder is gone.

## Acceptance criteria
1. The library lists all imported documents with their fields after restart. → test `LibraryModelTests/listsPersistedDocuments`
2. Each sort and filter returns the right order/subset, and filters combine. → tests `LibraryModelTests/sort*`, `LibraryModelTests/filter*`
3. Sort and layout persist; delete works through the model. → tests `sortAndLayoutPersist`, `deleteRemovesItem`

## Out of scope
- Views (T47), import (T48), metadata editing (T50).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
