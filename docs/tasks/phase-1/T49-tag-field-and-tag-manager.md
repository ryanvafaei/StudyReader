# T49: Tag field with autocomplete and the tag manager

- **Phase:** 1 (E1.5: F-10)
- **Agent:** ui-builder
- **Depends on:** T36, T45
- **ADRs:** none beyond ADR-0012 (through TagRepository)
- **Visual check needed:** yes

## Goal
A reusable tag field (chips + text field with autocomplete; typing a new name creates the tag) for highlights and documents, used by the popover (T62), browser (T69) and metadata sheet (T50); and the sidebar "Tags" section: tag list with counts, rename, merge, delete.

## Files to touch
- `StudyReader/Features/Annotations/Tags/TagFieldModel.swift` (new)
- `StudyReader/Features/Annotations/Tags/TagFieldView.swift` (new)
- `StudyReader/Features/Annotations/Tags/TagManagerModel.swift` (new)
- `StudyReader/Features/Annotations/Tags/TagManagerView.swift` (new)
- `StudyReader/App/RootView.swift` (modify: `.tags` shows `TagManagerView`)
- `StudyReaderTests/AnnotationsTests/TagFieldModelTests.swift`, `StudyReaderTests/AnnotationsTests/TagManagerModelTests.swift` (new)

## Interfaces to produce
```swift
enum TagTarget: Equatable, Sendable { case highlight(String), document(String) }

@MainActor @Observable
final class TagFieldModel {
    init(target: TagTarget, environment: AppEnvironment)
    private(set) var tags: [LibraryTag] = []       // assigned, name order
    var query: String = ""
    /// Up to 8 existing tags whose name starts with the trimmed query (case-insensitive, leading "#" ignored),
    /// excluding assigned ones, name order. Empty query → [].
    private(set) var suggestions: [LibraryTag] = []
    private(set) var errorMessage: String?

    func observe() async          // observes assigned tags (observeTags(forHighlight:/forDocument:)) and all tags
    /// findOrCreate(name:at: now()) then setTags(current + new). Clears query. Invalid name → errorMessage
    /// ("Tag names need 1 to 40 characters.").
    func add(name: String) async
    func remove(tagId: String) async
}

@MainActor @Observable
final class TagManagerModel {
    init(environment: AppEnvironment)
    private(set) var usage: [TagUsage] = []
    private(set) var errorMessage: String?
    func observe() async
    func rename(tagId: String, to name: String) async     // TagError → errorMessage (its errorDescription)
    func merge(sourceId: String, into targetId: String) async
    func delete(tagId: String) async
}
```
Views:
- `TagFieldView(model:)`: wrapping chips (`#name` with an × button, accessibility label "Remove tag name"), then a `TextField("Add tag", text: $model.query)`; Return adds the query; a suggestion list below while typing (click or ↓/Return to pick). Placeholder when no tags.
- `TagManagerView(session:)`: `List` of rows "name — N highlights, M documents"; context menu: Rename… (inline `TextField` or sheet), Merge into… (submenu of other tags), Delete… (confirmation "Delete tag "x"? It is removed from N highlights and M documents. They aren't deleted."). Toolbar: none needed. Empty state: "No tags yet" ("Add tags to highlights or documents, or write #tag in a highlight note").
- Filtering by tag in the library, browser, search and export uses those features' own filters (T47, T69, T66, T73).

## Tests
`TagFieldModelTests` (`@MainActor`, `AppEnvironment.inMemory()` + remove; a document and a highlight inserted):
- `suggestionsMatchPrefix`: tags "Exam", "Exercise", "ML"; query "ex" → ["Exam", "Exercise"]; after adding "Exam" → ["Exercise"]; query "#ml" → ["ML"].
- `addCreatesOrReuses`: `add(name: "exam")` assigns the existing "Exam" (no new tag); `add(name: "New one")` creates it; `add(name: "")` sets `errorMessage`.
- `documentTarget`: same add/remove against `.document(id)`.
`TagManagerModelTests`:
- `renameDuplicateShowsError`: rename "ML" to "exam" when "Exam" exists → `errorMessage == TagError.duplicateName.errorDescription`.
- `mergeAndDelete`: merge then delete update `usage` (poll bounded after `observe()` starts).

## Acceptance criteria
1. Autocomplete and create-on-type work for highlights and documents. → tests `TagFieldModelTests/*`
2. The tag manager renames, merges and deletes, with errors shown. → tests `TagManagerModelTests/*`
3. Visual check (user), right after this task: the Tags section shows the "No tags yet" empty state.
4. Visual check (user), done together with T50's check (tags can first be created in the metadata sheet): tags are listed with counts; rename, merge and delete work and the counts update.

## Out of scope
- Where the tag field appears (T50, T62, T69).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-25, Sonnet (code-reviewer, effort medium): APPROVED. 333 tests pass, 0 warnings. Visual check batched (VISUAL_CHECKS.md). Minor: model.usage not polled in tests, merge-title xcstrings key missing, arrow keys on TextField unverified.
