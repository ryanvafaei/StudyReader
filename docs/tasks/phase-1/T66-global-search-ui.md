# T66: Global search UI

- **Phase:** 1 (E1.6: F-12 global search)
- **Agent:** ui-builder
- **Depends on:** T52, T65
- **ADRs:** docs/decisions/0017-reader-windows-and-commands.md (router, commands)
- **Visual check needed:** yes

## Goal
A search field in the main window toolbar (⌘F in the library, ⌘⇧F from anywhere) that shows grouped results (Documents with page and snippet, Highlights, Notes) with the match in bold, filters (tag, category, type), and opens the document at the result's location.

## Files to touch
- `StudyReader/Features/Search/SearchModel.swift` (new)
- `StudyReader/Features/Search/SearchResultsView.swift` (new)
- `StudyReader/App/RootView.swift` (modify: `.searchable`, results replace the detail while a query is active)
- `StudyReader/App/AppCommands.swift`, `StudyReader/App/AppSession.swift` (modify)
- `StudyReaderTests/SearchTests/SearchModelTests.swift` (new)
- `StudyReader/Features/Library/LibraryView.swift` (modify: only if needed for the Constraint below)
- `StudyReaderUITests/LibraryOpenTests.swift` (modify: one test, Constraint below)

## Constraint (library window key equivalents, see docs/HANDOFF.md and T52i)
`LibraryView` has hidden key-equivalent buttons for the whole library window while the Library section is shown: Return opens the selected document (T52a) and Escape clears the selection (T52i). The search field is in the same window, so Return and Escape typed in it must act on the field: Return runs the search (`searchNow()`), Escape clears or leaves the field, and neither opens the selected document nor clears the library selection. Once a query is active, the results replace the detail column, so `LibraryView` (and its buttons) is out of the hierarchy; the risky case is Return or Escape in the focused field while the query is still empty or only whitespace. Handle it, for example by disabling the two buttons while `session.isSearchFocused` is true (pass it into `LibraryView`), and add the UI test `StudyReaderUITests/LibraryOpenTests/testReturnInTheSearchFieldDoesNotOpenTheSelectedDocument`: select a card, focus the search field (⌘F), type Return → no reader tab opens (`tabTitles.isEmpty`); type Escape, then check File > Edit Metadata… is still enabled.

## Interfaces to produce
```swift
@MainActor @Observable
final class SearchModel {
    static let debounceDelay: Duration = .milliseconds(150)
    init(environment: AppEnvironment)
    var query: String { didSet { scheduleSearch() } }        // Debouncer(debounceDelay, environment.sleeper)
    var filters = SearchFilters() { didSet { scheduleSearch() } }
    private(set) var results = SearchResults()
    private(set) var isSearching = false
    private(set) var errorMessage: String?
    var isActive: Bool { get }                                 // trimmed query non-empty
    func searchNow() async                                     // runs immediately (tests, Return key)

    /// Where a result opens (ADR-0017).
    nonisolated static func location(for hit: DocumentHit, query: String) -> ReaderLocation?   // .text → .searchHit(unitIndex:query:); title → nil
    nonisolated static func location(for hit: HighlightHit) -> ReaderLocation                 // .highlight(id)
    nonisolated static func location(for hit: NoteHit) -> ReaderLocation                      // highlight note → .highlight(id); document note → .documentNote
}

/// Splits a snippet on "**" and bolds the odd segments.
nonisolated func attributedSnippet(_ snippet: String) -> AttributedString
```
- `AppSession` gets `let search: SearchModel` and `var isSearchFocused: Bool` (bound to `.searchFocused`).
- `RootView`: `.searchable(text: $session.search.query, placement: .toolbar, prompt: "Search library")` with `.searchFocused($session.isSearchFocused)`; when `search.isActive`, the detail column shows `SearchResultsView` instead of the selected section.
- `SearchResultsView`: filter bar (Tag, Category, Type menus; "Clear"), then three sections with headers and counts: Documents (title, "p. N" for PDF text hits = unitIndex + 1, "Section N" for Markdown, snippet), Highlights (color bar, document title, page, snippet), Notes (icon highlight-note vs document-note, document title, snippet). Empty: "No results for "<query>"". Click → `session.router.open(documentId:at: location, using: openWindow)`.
- Commands: Search Library ⌘⇧F (selects the Library tab — documents are native tabs of the main window's tab group, ADR-0017 — by bringing the main window forward with `openWindow(id: "main")`, then sets `isSearchFocused = true`). Results open documents as tabs through the router. The existing Find ⌘F command from T52 becomes: reader focused → `findInDocument`; otherwise focus the library search (one command, one shortcut).

## Tests (`SearchModelTests`, `@MainActor`, in-memory environment with a `ManualSleeper` or `ImmediateSleeper`)
- `debouncedSearch`: set query "gra", "grad", "gradient" with a `ManualSleeper`; resume; results reflect "gradient" only (one search ran with the last query).
- `locations`: text hit with unitIndex 3 → `.searchHit(unitIndex: 3, query: q)`; title hit → nil; highlight hit → `.highlight(id)`; highlight-note hit → `.highlight(id)`; document note → `.documentNote`.
- `snippetBolding`: `attributedSnippet("a **b** c **d**")` has "b" and "d" bold, "a ", " c " not.
- `filtersTriggerSearch`: setting `filters.categoryId` reruns the search with the filter (results narrow).

## Acceptance criteria
1. Searches are debounced, map to the right open locations, and bold the match. → tests `SearchModelTests/*`
2. Visual check (user): ⌘⇧F from a document tab selects the Library tab and focuses its search; typing a word from a PDF page shows grouped results with the word in bold within a moment; clicking a page result opens the PDF at that page with the word selected (after T67; before T67 it opens at the page start or last position); clicking a highlight result opens the document's tab (or selects it if already open) scrolled to the highlight; a document-note result opens the Notes panel.
3. Visual check: phrase ("..."), prefix (word*) and -exclusion behave as expected; filters narrow results; clearing the field returns to the selected section.
4. Visual check (performance, informational): with the user's real library, results appear without noticeable delay (target < 200 ms, SPEC F-12).

## Out of scope
- In-document find and search-hit selection inside readers (T67).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
