# T69: Highlights browser

- **Phase:** 1 (E1.7: F-13 without Similar and Mastery)
- **Agent:** ui-builder
- **Depends on:** T49, T63, T68
- **ADRs:** docs/decisions/0017-reader-windows-and-commands.md (open in document)
- **Visual check needed:** yes

## Goal
Sidebar "Highlights": every highlight in the library as a list (color, rich text or thumbnail, note, tags, document title, page, created date), with the F-13 filters and sorts, multi-select bulk actions (add/remove tag, change color, delete), and a detail pane (full highlight, editable note and tags, "Open in Document"). "Export selection" is added by T73; Similar and Mastery come in Phases 2–3.

## Files to touch
- `StudyReader/Features/HighlightsBrowser/HighlightsBrowserModel.swift` (new)
- `StudyReader/Features/HighlightsBrowser/HighlightsBrowserView.swift` (new: filter bar, list, bulk bar)
- `StudyReader/Features/HighlightsBrowser/HighlightDetailView.swift` (new)
- `StudyReader/App/RootView.swift` (modify: `.highlights` route)
- `StudyReaderTests/HighlightsBrowserTests/HighlightsBrowserModelTests.swift` (new)

## Constraint (library window key equivalents, see docs/HANDOFF.md and T52i)
`LibraryView` has hidden key-equivalent buttons for the whole main window while it is in the hierarchy: Return opens the selected document (T52a) and Escape clears the selection (T52i). The Highlights browser's text fields (note editor, tag field, "Add Tag…" popover, date pickers) live in the same window. They are safe only because the Highlights section replaces `LibraryView` in the detail column (`RootView`). Keep it that way: don't keep `LibraryView` mounted (for example in a `ZStack` or `TabView` to preserve its state) while the Highlights section is shown. If you must, Return and Escape typed in the browser's fields must not open the selected document or clear the library selection, with a UI test that proves it.

## Interfaces to produce
```swift
@MainActor @Observable
final class HighlightsBrowserModel {
    init(session: AppSession)
    var filter = HighlightBrowserFilter() { didSet { restartObservation() } }
    var sort: HighlightBrowserSort = .createdNewest { didSet { restartObservation() } }
    private(set) var items: [HighlightListItem] = []
    var selection: Set<String> = []
    private(set) var errorMessage: String?
    var selectedItems: [HighlightListItem] { get }             // items whose id is in selection, in list order
    var detailItem: HighlightListItem? { get }                 // the single selected item, else nil

    func observe() async                                       // observeBrowse(filter:sort:) until cancelled; restarts on change
    /// Bulk actions on `selection` (SPEC F-13); each clears nothing but refreshes through observation.
    func addTag(named name: String) async                      // tagRepository.findOrCreate + addTag(toHighlights:)
    func removeTag(_ tagId: String) async                      // tagRepository.removeTag(fromHighlights:)
    func setColor(_ color: HighlightColor) async               // highlightService.setColor(ids:)
    func deleteSelected() async                                // highlightService.delete(ids:); selection = []
    /// Tags present on at least one selected highlight (for the "Remove Tag" menu).
    var tagsInSelection: [LibraryTag] { get }
}
```
- `restartObservation()`: cancel the current observation task and start a new one (keep the `Task` in the model).
- **As built (backlog pass 2026-10-28, BACKLOG B26 3):** `init(environment: AppEnvironment, calendar: Calendar = .current)`; `filter` and `sort` have no `didSet`; the view restarts `observe()` with `.task(id: model.query)` (`HighlightBrowseQuery` = filter + sort) instead of `restartObservation()`. The model also holds `hasLoaded`, the filter-menu lookups (`observeLookups()`), `thumbnails`, and `exportSelection()` / `exportMessage` (T73). The list and detail sit in an `HStack` (T69a), not an `HSplitView`.
- View: top filter bar — Document (multi-select popover list), Category, Tag (multi-select + Any/All segmented), Color (five toggles), Note (Any / With note / Without note), View (PDF / Text / Markdown), Date range (two optional `DatePicker`s: "From" day start, "To" → `createdBefore` = next day start, computed with `Calendar.current`), "Clear". Sort menu (Newest first, Document and position, Color).
- List: `List(selection: $model.selection)` rows: color bar, `RichTextView` (or image thumbnail via `fileStore.url(forRelativePath: imagePath)`), note excerpt, `#tags`, document title · "p. N" · created date (`.dateTime.day().month().year()`). Orphaned highlights show "Couldn't locate in document".
- Bulk bar (visible when `selection.count > 1`): "Add Tag…" (text field popover with autocomplete from `tagRepository.observeAll()`), "Remove Tag" menu (`tagsInSelection`), color menu, "Delete" (confirmation "Delete N highlights?").
- Detail pane (when one item is selected): full rich text or image, `NoteEditorModel(.highlight(id))` editor, `TagFieldView(model: TagFieldModel(target: .highlight(id)))`, color dots, "Open in Document" → `session.router.open(documentId:at: .highlight(id), using: openWindow)`.
- Empty: "No highlights yet" / "No highlights match these filters" + Clear.

## Tests (`HighlightsBrowserModelTests`, `@MainActor`, in-memory environment + session; same fixture shape as T68)
- `filterCategoryAndColor`, `filterTagAll`, `filterHasNote`, `filterDateRange`: set `filter`, poll (bounded) until `items` reflects it.
- `sortDocumentPosition`, `sortColor`.
- `filtersCombine`: three filters at once.
- `bulkActions` (SPEC F-13 AC2): select 3; `addTag(named: "exam")` → all 3 tagged; `removeTag(examId)` → none; `setColor(.green)` → all green; `deleteSelected()` → gone and `selection` empty.
- `detailItemOnlyForSingleSelection`.

## Acceptance criteria
1. Every filter and sort works and combines. → tests `HighlightsBrowserModelTests/filter*`, `sort*`, `filtersCombine` (with T68's query tests), SPEC F-13 AC1
2. Bulk actions apply to all selected highlights. → test `HighlightsBrowserModelTests/bulkActions` (SPEC F-13 AC2)
3. Visual check (user): open Highlights; all highlights are listed with color, text or thumbnail (image highlights, SPEC F-08 AC2), note, tags, document, page and date; each filter narrows the list; sorts reorder; multi-select with ⌘-click and use each bulk action; the detail pane edits note and tags; "Open in Document" opens the reader at the highlight.

## Out of scope
- Similar (Phase 3), Mastery and its filter (Phase 2), Export selection (T73).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-28, implementer ui-builder Sonnet medium (rework 1: high), reviewer code-reviewer Sonnet medium: CHANGES REQUESTED (1st): (1) blocker: colour filter button label 'Filter by yellow' (HighlightPalette.name lowercase) vs UI test buttons['Filter by Yellow']: use HighlightPalette.title; (2) major: no String Catalog plural variations for '%lld highlights' / 'Delete %lld highlights?' (precedent T52g). Minor: thumbnail race after cancelled observe (merge or check Task.isCancelled); testReturnAndEscapeDoNothingToTheLibrary is weak (select a row / focus the note field); count label should be a value.
- 2026-10-28, implementer ui-builder Sonnet medium (rework 1: high), reviewer code-reviewer Sonnet high: APPROVED (2nd, conditional on the full unit run). Label, plural variations (T52g shape), thumbnail race, stronger Return/Escape test fixed; HighlightsBrowserModelTests incl. new count/delete-title tests pass on CI; the UI tests are unrun (T69 checkpoint compiles and runs them). Minor items to BACKLOG B26.
