# T47: Library view: grid and list, covers, context menu, delete

- **Phase:** 1 (E1.1: F-01)
- **Agent:** ui-builder
- **Depends on:** T44, T45, T46
- **ADRs:** docs/decisions/0016-import-pipeline-and-stored-files.md (covers), docs/decisions/0017-reader-windows-and-commands.md (LibraryActions)
- **Visual check needed:** yes

## Goal
The Library section of the main window (SPEC F-01): grid (default) or list of documents with cover, title, author, category, highlight count, reading progress and last opened; sort, filter and layout controls; per-document context menu; delete with confirmation; extraction status.

## Files to touch
- `StudyReader/Features/Library/LibraryView.swift` (new: toolbar, grid, list, empty state)
- `StudyReader/Features/Library/LibraryItemViews.swift` (new: grid card, list row, status badge)
- `StudyReader/Features/Library/DocumentCoverView.swift` (new: stored cover or generated card)
- `StudyReader/Features/Library/LibraryActions.swift` (new: FocusedValue for menu commands)
- `StudyReader/App/RootView.swift` (modify: `.library` shows `LibraryView`)

## Interfaces to produce
```swift
/// Published by the library with .focusedSceneValue so menu commands can act on the selection (ADR-0017).
struct LibraryActions {
    var selectedDocumentId: String?
    var editMetadata: (@MainActor (String) -> Void)?    // set by T50
    var exportHighlights: (@MainActor (String) -> Void)? // set by T73
}
extension FocusedValues { @Entry var libraryActions: LibraryActions? }

struct DocumentCoverView: View {
    init(document: LibraryDocument, categoryName: String, fileStore: FileStore)
    // coverPath non-nil and the file loads (NSImage(contentsOf: fileStore.url(forRelativePath:))) → that image,
    // aspect fit in a 3:4 frame; otherwise GeneratedCoverView: rounded rect tinted by fileType
    // (PDF: secondary system fill, Markdown: accent at 15 % opacity), title (3 lines max) and a doc icon.
}
```
Layout and behaviour:
- `LibraryView(session: AppSession)` owns `@State var model = LibraryModel(environment:)` and runs `.task { await model.observe() }`.
- Toolbar: Sort menu (Date Added, Last Opened, Title, Author; checkmark on current), Filter menu (Category submenu from `categoryRepository.observeAll()`, Tag submenu from `tagRepository.observeAll()`, File Type (PDF / Markdown), "Has Highlights", "Clear Filters"), layout picker (grid/list, segmented, SF Symbols `square.grid.2x2` / `list.bullet`).
- Grid: `LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 220))])`; card = cover, title (2 lines), author (1 line, secondary), category · "N highlights", progress (`ProgressView(value:)` + "NN %"), last opened (`Text(date, format: .relative(presentation: .named))` or "Never opened").
- List: `Table` with columns Title, Author, Category, Highlights, Progress, Last Opened, Added; sortable headers aren't needed (the Sort menu drives order).
- Selection: single selection; double-click or Return opens the document — leave an `openDocument(_ id: String)` method on the view that does nothing until T52 wires the reader (comment `// T52`).
- Context menu per item: Open (same hook), Edit Metadata… (calls `libraryActions.editMetadata` hook; disabled until T50 sets it), Reveal Original in Finder (resolve `originalBookmark` with `URL(resolvingBookmarkData:options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale:)`; on success `NSWorkspace.shared.activateFileViewerSelecting([url])`; disabled when the bookmark is nil; on failure show "The original file is no longer available."), Export Highlights… (hidden until T73), Delete… (confirmation dialog: title "Delete "<title>"?", message "This removes the document, its highlights, notes and review cards from StudyReader. The original file isn't touched.", destructive "Delete").
- Status badge on items: extraction `pending` → small `ProgressView` + "Indexing…"; `failed` → "Text extraction failed" + "Retry" button (`model.retryExtraction`).
- Empty library: `ContentUnavailableView("No documents yet", systemImage: "books.vertical", description: Text("Drop PDF or Markdown files here, or choose File > Import…"))`. Empty filter result: "No documents match these filters" + "Clear Filters".
- Accessibility: each card has a combined label "title, author, category, N highlights, NN percent read".
- `model.errorMessage` shows as an alert.

## Acceptance criteria
1. Visual check (user), done together with T48's check, because documents can only be imported once T48 lands (right after this task, the user only checks the empty state): grid shows cover (PDF first page / generated card for Markdown), title, author, category, highlight count, progress and last opened; switching to list shows a table with the same data; the layout and sort survive relaunch.
2. Visual check: each sort option reorders as specified; each filter narrows the list; "Clear Filters" restores it.
3. Visual check: Delete asks for confirmation and removes the item; Reveal Original in Finder selects the original file.
4. Visual check: a document with `extractionStatus = failed` shows "Text extraction failed" and Retry.
5. Visual check right after this task: the Library section shows the "No documents yet" empty state and the toolbar menus.
6. Full suite passes (no new tests; logic is in T46).

## Out of scope
- Import UI and drop targets (T48), metadata sheet (T50), document tabs (T52), export (T73).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-25, Sonnet (code-reviewer, effort medium): APPROVED after user visual check (incl. DEBUG sample library, cover status overlay, compact list status, onChange fix). 315 tests pass, 0 warnings. Minor: DocumentCoverView.categoryName unused; grid right-click/Return selection and a11y traits deferred to T52.
