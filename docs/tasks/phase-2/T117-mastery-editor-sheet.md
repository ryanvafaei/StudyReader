# T117: Mastery editor sheet

- **Phase:** 2 (E2.3 Mastery; SPEC F-16 manual cloze and Q&A)
- **Agent:** ui-builder
- **Depends on:** T115
- **ADRs:** **ADR-0021** (cloze ranges are UTF-16 offsets into the card's text), ADR-0005 (NSTextView for selection)
- **Visual check needed:** yes (Mac row below)
- **UI tests:** none in this task; T128 covers it. Verify with `./scripts/build.sh` and the filter in criterion 6.

## Goal
"Mastery…" opens a sheet where the user turns one highlight into active-recall cards: select words in the highlight text and hide them (each cloze card hides one or more spans), or write a question whose answer defaults to the highlight text. Existing Mastery cards are listed, can be changed or removed, and Save applies everything at once. Entry points are T118 (browser) and T119 (reader popover).

## Files to touch
- `StudyReader/Features/Review/Mastery/MasteryEditorModel.swift` (new)
- `StudyReader/Features/Review/Mastery/MasteryEditorSheet.swift` (new)
- `StudyReader/Features/Review/Mastery/ClozeSelectionTextView.swift` (new: `NSViewRepresentable`)
- `StudyReaderTests/ReviewTests/MasteryEditorModelTests.swift` (new)

## Interfaces to produce
```swift
@MainActor @Observable
final class MasteryEditorModel {
    init(highlightId: String, environment: AppEnvironment)
    private(set) var sourceText = ""              // MasteryService.clozeSourceText
    private(set) var isImageHighlight = false
    private(set) var drafts: [MasteryDraft] = []
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    /// The current selection in the cloze text view (UTF-16, from NSTextView.selectedRange). nil or empty = none.
    var selection: ClozeRange?
    /// The draft the editor shows (its ranges are tinted in the text view; its Q&A fields are editable).
    var selectedDraftId: String?

    func load() async                             // sourceText, drafts (MasteryService.drafts), image flag
    var canAddCloze: Bool { get }                 // !isImageHighlight && selection has length > 0
    func addCloze()                               // new unsaved cloze draft with [selection]; selects it; clears selection
    func addSelectionToSelectedCloze()            // appends selection to the selected cloze draft's ranges (normalized)
    func addQuestion()                            // new unsaved qa draft: question "", answer = sourceText; selects it
    func updateQuestion(_ text: String, for draftId: String)
    func updateAnswer(_ text: String, for draftId: String)
    func remove(_ draftId: String)
    /// MasteryService.save(drafts, highlightId:). true on success; false with errorMessage (the MasteryError text).
    func save() async -> Bool
    var isDirty: Bool { get }                     // drafts differ from what load() read
}
```

## What to do
1. **Sheet layout** (width ~560, title "Mastery"):
   - Top: the highlight text in `ClozeSelectionTextView` (non-editable, selectable `NSTextView`, body font, ~6 lines tall, scrolls) reporting `selectedRange()` as `ClozeRange` into `model.selection` and tinting the selected cloze draft's ranges with a background colour. For an image highlight show the snapshot instead (via `FileStore.url(forRelativePath:)`, loaded once) and the note "Image highlights can have question cards only."
   - Buttons under the text: "Hide Selection as New Card" (`model.addCloze()`, disabled unless `canAddCloze`), "Hide Selection in This Card" (`addSelectionToSelectedCloze()`, only when a cloze draft is selected), "Add Question" (`addQuestion()`).
   - A list of drafts: each row shows its type ("Cloze" / "Question") and a preview (cloze: `RichTextView(ClozeText.front(…))` using the card's text: `sourceText` for unsaved drafts; question text for Q&A), a "Saved" or "New" caption, and a remove button ("Remove card").
   - For the selected Q&A draft: `TextField("Question", …)` and a `TextEditor` for the answer (min 3 lines).
   - Bottom: error text, "Cancel" (`.keyboardShortcut(.cancelAction)`), "Save" (no default-action shortcut: the answer editor is multi-line). Save → `await model.save()`; close on true.
2. The sheet is presented by its host (T118, T119) with `.sheet(item:)`; it gets `highlightId` and `session`. Closing with unsaved changes needs no confirmation (Cancel discards).
3. `ClozeSelectionTextView` uses the `NSTextView` selection directly (UTF-16 `NSRange`), so offsets match `ClozeText` (ADR-0021). Keep it small: `makeNSView` builds a scrollable non-editable text view; `updateNSView` sets the string only when it changed and re-applies the tint; the delegate's `textViewDidChangeSelection` writes `model.selection`.

## Constraint (HANDOFF standing rule, Library Return/Escape)
When opened from the Highlights browser the sheet belongs to the main window. `LibraryView` is not mounted in the Highlights section (T69): keep it so. Return in the Question field and in the answer editor must not open a document or change the library selection; Escape closes the sheet (Cancel) and must not clear the library selection. T128 proves it (`MasteryEditorTests/testReturnAndEscapeStayInTheSheet`).

## Acceptance criteria
`@MainActor` tests with an in-memory environment (documents and highlights through repositories; end with `FTSIntegrity.check`).
1. `MasteryEditorModelTests/loadReadsTextAndDrafts`: a highlight with one saved qa card → `sourceText` = its text, one saved draft, `hasLoaded`, not dirty.
2. `MasteryEditorModelTests/addClozeFromSelection`: selection (4, 12) → `addCloze()` adds a draft with that range, selects it, clears `selection`, `isDirty`; `addSelectionToSelectedCloze()` with (20, 3) gives two ranges; an empty selection can't add.
3. `MasteryEditorModelTests/addQuestionDefaultsAnswer`: answer = `sourceText`; `updateQuestion`/`updateAnswer` change only that draft.
4. `MasteryEditorModelTests/saveAppliesAndReportsErrors`: a qa draft with an empty question → `save()` false, `errorMessage == "Write a question."`, no card; fixed → true, the card exists, passive suspended; removing it and saving deletes it.
5. `MasteryEditorModelTests/imageHighlightHasNoCloze`: `isImageHighlight`, `canAddCloze == false` even with a selection.
6. `./scripts/test.sh StudyReaderTests/MasteryEditorModelTests` passes; `./scripts/build.sh` succeeds.
7. Report "Visual check needed: yes" with this Mac row. **T117 Mastery editor** (Mac, after T118; light and dark): select a word in the text, "Hide Selection as New Card" → a Cloze row with "[…]" in its preview and the word tinted; select a second word, "Hide Selection in This Card" → both tinted, two "[…]"; Add Question → the answer is the highlight text, edit both; Save → the sheet closes and the highlight shows "Mastery"; reopen → the two cards are listed as Saved; remove one, Save → one left; on a snapshot highlight only Add Question is offered; offsets stay right with accented letters and emoji in the text.

## Out of scope
- "Suggest with Apple Intelligence" (Phase 3, ADR-0010). The entry points and badges (T118, T119).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
