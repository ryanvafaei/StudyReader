# T37: Document notes, `#tag` parsing and the note autosave model

- **Phase:** 1 (E1.5: F-09, F-10)
- **Agent:** data-layer
- **Depends on:** T33, T35, T36
- **ADRs:** docs/decisions/0012-data-layer-conventions.md (PK upsert only), docs/decisions/0015-settings-and-injected-sleep.md (Debouncer, Sleeper)
- **Visual check needed:** no

## Goal
Notes autosave 500 ms after typing stops and survive restart (F-09); `#tagname` in a highlight note adds the tag (F-10). One model, `NoteEditorModel`, edits either a highlight note or the document note; the popover (T62), side panel (T63) and browser (T69) reuse it.

## Files to touch
- `StudyReader/Core/Repositories/NotesRepository.swift` (new)
- `StudyReader/Features/Annotations/TagParsing.swift` (new)
- `StudyReader/Features/Annotations/NoteEditorModel.swift` (new)
- `StudyReader/App/AppEnvironment.swift` (modify: add `let notesRepository: NotesRepository`)
- `StudyReaderTests/AnnotationsTests/NotesRepositoryTests.swift`, `StudyReaderTests/AnnotationsTests/TagParsingTests.swift` (new)

## Interfaces to produce
```swift
struct NotesRepository: Sendable {
    init(database: AppDatabase)
    func documentNote(documentId: String) async throws -> DocumentNote?
    /// DocumentNote(documentId:, body:, updatedAt: date).upsertAndFetch(db, onConflict: ["documentId"]) (ADR-0012: PK target).
    func saveDocumentNote(documentId: String, body: String, at date: Date) async throws
    func observeDocumentNote(documentId: String) -> AsyncValueObservation<DocumentNote?>
}

enum TagParsing {
    /// Tag names written as #name in `text`, in order of first appearance, deduplicated case-insensitively
    /// (first spelling kept). Rules:
    /// - "#" must be at the start of the text or follow whitespace or "(".
    /// - name = the longest run of letters, digits, "_" or "-" after "#"; 1–40 characters, else ignored.
    /// - "# heading", "##x" (the second # isn't a name character) and "a#b" give nothing.
    /// - Text inside `backticks` is ignored.
    static func hashTags(in text: String) -> [String]
}

@MainActor @Observable
final class NoteEditorModel {
    enum Target: Equatable, Sendable { case highlight(String), document(String) }
    static let autosaveDelay: Duration = .milliseconds(500)

    let target: Target
    /// Set by the view on every edit. Setting it schedules a save (Debouncer, autosaveDelay, environment.sleeper).
    var text: String
    private(set) var isLoaded: Bool
    private(set) var lastError: String?            // user-facing, set when a save fails

    init(target: Target, environment: AppEnvironment)
    /// Loads the stored text without scheduling a save.
    func load() async
    /// Saves the pending text now (await). Views call it on disappear.
    func flush() async
}
```
Saving:
- `.document(id)` → `notesRepository.saveDocumentNote(documentId:body:at: environment.now())`.
- `.highlight(id)` → `highlightRepository.updateNote(id:note:at: now())`, then for each name in `TagParsing.hashTags(in: text)`: `tagRepository.findOrCreate(name:at:)` and `tagRepository.addTag(tag.id, toHighlights: [id])`. Removing `#x` from the note never removes the tag.
- Saving the same text that was loaded or last saved does nothing.
- Use `didSet` on `text` guarded by `isLoaded` (setting `text` inside `load()` must not schedule a save).

## Tests
`NotesRepositoryTests` (on-disk where stated, with `TestFileStore.make()` + `defer remove`):
- `autosaveAndRestore` (SPEC F-09 AC1): on-disk `AppEnvironment.make(fileStore:now:settingsStore:)` with `FixedNow(TestData.referenceDate)`, but build the environment with a `ManualSleeper` — add the sleeper by constructing `AppEnvironment(fileStore:database:now:settingsStore:sleeper:)` over `AppDatabase.makeShared(fileStore:)`. Insert a document and a highlight. Document note model: `load()`, set `text` to "a", "ab", "abc"; `await sleeper.waitForSleepers(3)`; `await sleeper.resumeAll()`; poll (bounded) until the stored note body is "abc". Highlight note model: set text, `flush()`; stored. Then open a second `AppDatabase.makeShared` on the same store (after dropping the first environment) and check both notes are there; a new `NoteEditorModel.load()` shows them. `FTSIntegrity.check` on the reopened database.
- `onlyLastEditIsSaved`: with the `ManualSleeper`, observe that no save happens before `resumeAll()` (stored body still empty), and after it the body equals the last text.
- `hashTagsAddTagsOnSave`: highlight note "Review #Exam and #ml-basics, see #exam" → after `flush()`, the highlight has tags "Exam" and "ml-basics" (2 links). Then text "nothing" + flush → tags unchanged.
- `documentNoteUsesPrimaryKeyUpsert`: saving twice keeps one `documentNote` row with the latest body and `updatedAt`.

`TagParsingTests`:
- `hashTags` (SPEC F-10 AC2): `"Review #Exam and #ml-basics, see #exam"` → `["Exam", "ml-basics"]`; `"# Heading"` → `[]`; `"a#b"` → `[]`; `"(#tag)"` → `["tag"]`; `` "`#code` #real" `` → `["real"]`; `"##x"` → `[]`; a 41-character name → `[]`; `"#Über"` → `["Über"]`; `"line1\n#next"` → `["next"]`.

## Acceptance criteria
1. Notes autosave 500 ms after the last edit and survive restart. → tests `NotesRepositoryTests/autosaveAndRestore`, `onlyLastEditIsSaved`
2. `#tag` in a highlight note adds the tag and never removes one. → tests `TagParsingTests/hashTags`, `NotesRepositoryTests/hashTagsAddTagsOnSave`
3. Document notes use the primary-key upsert only. → test `NotesRepositoryTests/documentNoteUsesPrimaryKeyUpsert`
4. Writing tests end with `FTSIntegrity.check`; full suite passes.

## Out of scope
- Note UI and Markdown rendering of notes (T62, T63).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
