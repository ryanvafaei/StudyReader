# T50: Edit Metadata sheet and the category manager

- **Phase:** 1 (E1.1: F-11; document tags for F-10)
- **Agent:** ui-builder
- **Depends on:** T39, T47, T49
- **ADRs:** docs/decisions/0016-import-pipeline-and-stored-files.md (covers), docs/decisions/0017-reader-windows-and-commands.md (LibraryActions)
- **Visual check needed:** yes

## Goal
Edit a document's title, author, category, tags and cover (SPEC F-11), from the library context menu or ⇧⌘M; and the sidebar "Categories" section to add, rename and delete custom categories (deleting reassigns documents to Other).

## Files to touch
- `StudyReader/Features/Library/Metadata/MetadataEditorModel.swift` (new)
- `StudyReader/Features/Library/Metadata/MetadataSheet.swift` (new)
- `StudyReader/Features/Library/Categories/CategoryManagerModel.swift` (new)
- `StudyReader/Features/Library/Categories/CategoryManagerView.swift` (new)
- `StudyReader/Features/Library/LibraryView.swift` (modify: present the sheet, set `LibraryActions.editMetadata`)
- `StudyReader/App/AppCommands.swift`, `StudyReader/App/RootView.swift` (modify: ⇧⌘M command; `.categories` route)
- `StudyReaderTests/LibraryTests/MetadataEditorModelTests.swift`, `StudyReaderTests/LibraryTests/CategoryManagerModelTests.swift` (new)

## Interfaces to produce
```swift
@MainActor @Observable
final class MetadataEditorModel {
    /// currentPageIndex: set when opened from a PDF reader, enables "Use Current Page".
    init(documentId: String, currentPageIndex: Int?, session: AppSession)
    private(set) var document: LibraryDocument?
    var title: String = ""
    var author: String = ""
    var categoryId: String = ""
    private(set) var categories: [DocumentCategory] = []
    private(set) var errorMessage: String?
    private(set) var coverVersion: Int = 0     // bump after a cover change so the view reloads the image
    var canUseCurrentPage: Bool { get }         // PDF and currentPageIndex != nil

    func load() async
    /// documentRepository.updateMetadata(id:title:author:categoryId:). DocumentEditError.emptyTitle → errorMessage.
    /// Returns true on success (the sheet closes).
    func save() async -> Bool
    func chooseCoverImage(_ url: URL) async     // security-scoped access around CoverService.setCustomCover
    func useCurrentPageAsCover() async          // CoverService.usePageAsCover(pageIndex: currentPageIndex!)
    func resetCover() async                     // CoverService.resetCover
}

@MainActor @Observable
final class CategoryManagerModel {
    init(session: AppSession)
    private(set) var usage: [CategoryUsage] = []
    private(set) var errorMessage: String?
    func observe() async
    func create(name: String) async
    func rename(id: String, to name: String) async
    /// categoryRepository.delete; if id == settings.defaultCategoryId, reset it to BuiltinCategory.lectureSlides.id.
    func delete(id: String) async
}
```
- `CoverService` comes from `CoverService(fileStore: environment.fileStore, documents: environment.documentRepository)`.
- Metadata sheet (fixed width 460): cover preview (`DocumentCoverView`, keyed by `coverVersion`) with buttons "Choose Image…" (`.fileImporter` with `[.image]`), "Use Current Page" (only when `canUseCurrentPage`), "Reset"; fields Title, Author, Category picker, Tags (`TagFieldView` with `TagFieldModel(target: .document(id))`); Cancel / Save (⌘Return). Tag changes save immediately (as the field does); Cancel only discards title/author/category edits.
- Library: context menu "Edit Metadata…" and ⇧⌘M (via `LibraryActions.editMetadata` for the selected document) present the sheet. T52 extends the same command for document tabs (passing the current page).
- Category manager (sidebar "Categories"): list "name — N documents"; built-ins show a lock icon and no rename/delete; "+" button / "New Category…" adds; context menu Rename… / Delete… (confirmation "Delete category "x"? Its N documents move to Other."). `CategoryError` texts shown as alerts.

## Tests
`MetadataEditorModelTests` (`@MainActor`, `AppEnvironment.inMemory()` + remove, `AppSession(environment:)`; a PDF document whose original is the `coloredRegion` fixture copied into its folder):
- `loadAndSave`: load shows stored values; change title/author/category; `save()` returns true; the row has them (SPEC F-11 AC2 via the UI model).
- `emptyTitleShowsError`: title "  " → `save()` false, `errorMessage` set, row unchanged.
- `coverActions`: `useCurrentPageAsCover()` with `currentPageIndex: 0` → `coverSource == .page`, `coverVersion` incremented; `resetCover()` → `.automatic`; `canUseCurrentPage` false for a Markdown document or nil page.
`CategoryManagerModelTests`:
- `deleteResetsDefaultCategory`: create "Lab", set it as `settings.defaultCategoryId`, delete it → setting is Lecture slides' id; documents in it moved to Other.
- `errorsAreShown`: rename a built-in → `errorMessage == CategoryError.builtinCategory.errorDescription`.

## Acceptance criteria
1. Metadata edits persist; empty titles are refused; cover actions update the row. → tests `MetadataEditorModelTests/*`
2. Custom categories can be managed; deleting the default resets the setting. → tests `CategoryManagerModelTests/*`
3. Visual check (user): right-click a document → Edit Metadata…; change title, author, category, add two tags, choose a cover image → Save; the library card updates at once; ⇧⌘M opens the same sheet for the selected document; Reset restores the first-page cover.
4. Visual check: in Categories, add "Lab reports", rename it, assign a document to it, delete it → the document shows "Other"; built-ins can't be renamed or deleted.
5. Visual check: T49's deferred check 4 (tag manager with the tags added here: counts, rename, merge, delete).

## Out of scope
- Search UI (T66), exports (T70+). Category review frequency (Phase 2).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
