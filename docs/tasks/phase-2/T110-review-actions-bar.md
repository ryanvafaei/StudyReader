# T110: Review actions: note, edit highlight, show original, frequency, open in document, skip

- **Phase:** 2 (E2.2 Daily review; SPEC F-18)
- **Agent:** ui-builder
- **Depends on:** T109
- **ADRs:** **ADR-0022** (keys typed in a field never rate), ADR-0017 (open in document), ADR-0015
- **Visual check needed:** yes (Mac row below)
- **UI tests:** none in this task; T112 covers it (incl. the key rule below). Verify with `./scripts/build.sh` and the filter in criterion 5.

## Goal
Under the review card, one row of actions that work on the current card and persist at once (F-18): Note (inline editor), Edit (inline editor for the highlight's display text, plus "Show Original"), Frequency menu, Open in Document, Skip.

## Files to touch
- `StudyReader/Features/Review/ReviewActionsBar.swift` (new)
- `StudyReader/Features/Review/ReviewCardView.swift` (modify: host the bar and the two inline editors)
- `StudyReader/Features/Review/ReviewEditDraft.swift` (new: tiny `@MainActor @Observable` draft model, unit-tested)
- `StudyReaderTests/ReviewTests/ReviewEditDraftTests.swift` (new)

## Interfaces to produce
```swift
/// Draft for "Edit highlight" (SPEC F-18). Starts with editedText ?? text; save returns what to store.
@MainActor @Observable
final class ReviewEditDraft {
    init(highlight: Highlight)
    var text: String
    var isChanged: Bool { get }                  // text differs from the starting text
    /// nil when the text is whitespace-only or equals highlight.text (the edit is removed), else the text as typed.
    var valueToStore: String? { get }
}
```

## What to do
1. **Bar** (under the rating row; plain bordered buttons with SF Symbols and text; identifiers in brackets):
   - **Note** [`review-action-note`]: toggles an inline note editor under the card: `TextEditor` bound to a `NoteEditorModel(target: .highlight(current.highlight.id), environment:)` (`load()` on appear, autosaves after 500 ms like everywhere else) [`review-note-editor`]. Flush it (`await noteModel.flush()`) before the card changes (rate, skip, frequency Off) and on disappear, then `await model.reloadCurrent()` so the passive card shows the new note.
   - **Edit** [`review-action-edit`]: text highlights only (disabled for image highlights). Shows an inline `TextEditor` with a `ReviewEditDraft` [`review-edit-editor`] and "Save" [`review-edit-save`] / "Cancel" [`review-edit-cancel`] buttons; Save → `await model.editHighlightText(draft.valueToStore)`, then close the editor.
   - **Show Original** [`review-show-original`]: a toggle bound to `model.showOriginal`, shown only when `content.isEdited`.
   - **Frequency** menu [`review-action-frequency`]: "Category default (<category frequency name>)" (override nil), then Off, Low, Normal, High, with a checkmark on the current choice (`current.card.frequencyOverride`). Choosing → `await model.setFrequency(…)`. Footnote text in the menu isn't needed.
   - **Open in Document** [`review-action-open`]: `session.router.open(documentId: current.highlight.documentId, at: .highlight(current.highlight.id), using: openWindow)` (`@Environment(\.openWindow)`). The session stays where it is.
   - **Skip** [`review-action-skip`]: `model.skip()`.
2. While an editor is open, the rating buttons stay clickable but the keys go to the editor (the card container loses focus to the `TextEditor`, so `.onKeyPress` doesn't fire). Don't add any key handling to the editors. When an editor closes, give the focus back to the card container.
3. Each action disables itself while `model.isBusy`.

## Constraint (HANDOFF standing rule, Library Return/Escape; ADR-0022)
The two `TextEditor`s are text fields in the main window. `LibraryView` (with its window-wide hidden Return and Escape buttons) is not mounted while the Review section shows (`RootView` replaces the detail column, T109): keep it that way. In addition:
- Return in an editor inserts a line break: it never opens a document, rates, reveals or saves.
- Escape in an editor never clears anything in the library and doesn't rate; it may leave the field (standard behaviour).
- Space and the digits 1–4 typed in an editor are text: they never reveal or rate.
T112 proves all three with a UI test (`ReviewSessionTests/testKeysInTheNoteFieldDoNotRate`, `testReturnAndEscapeInTheEditFieldDoNothingElse`).

## Acceptance criteria
1. `ReviewEditDraftTests/startsWithEditedOrOriginal`: highlight with `editedText` "B" → text "B"; without → its `text`.
2. `ReviewEditDraftTests/valueToStoreRules`: whitespace-only → nil; the original `text` → nil; "New" → "New"; `isChanged` false until the text changes.
3. Reviewer: no `.keyboardShortcut` without modifiers added; the note editor is `NoteEditorModel` (no second autosave path); the edit goes through `ReviewSessionModel.editHighlightText`.
4. `./scripts/build.sh` succeeds.
5. `./scripts/test.sh StudyReaderTests/ReviewEditDraftTests StudyReaderTests/ReviewSessionModelTests` passes.
6. Report "Visual check needed: yes" with this Mac row. **T110 Review actions** (Seed Sample Library, light and dark): Note opens an editor under the card, typed text survives Skip and a relaunch, the passive card shows it; Edit changes the shown text, "Show Original" toggles back and forth, the Highlights browser row shows the edited text; Frequency menu shows "Category default (High)" checked for a Lecture card, Off removes the card from the session, High keeps it; Open in Document opens the reader tab at the highlight and the session is still there when you come back; Skip moves the card to the end ("1 of 8" stays, the card returns last); typing "1", "2", Space and Return in both editors only types.

## Out of scope
- Mastery editing from the review screen (Flashcards view, T127, and the browser, T118).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
- 2026-10-29, implementer ui-builder sonnet medium, reviewer code-reviewer sonnet medium: CHANGES REQUESTED (1st), (1) opening Note/Edit does not move focus into the editor, so 1/2/Space typed before clicking in can still rate/reveal (ADR-0022 failure); (2) onSkip flushes the note but never calls reloadCurrent, so the skipped card returns with a stale note
- 2026-10-29, implementer ui-builder sonnet high (rework 1, effort high: focus handoff + onKeyPress guard while an editor is open; reloadCurrent before skip), reviewer code-reviewer sonnet high: APPROVED, both findings fixed; CI build and full unit tests green, 866 tests (runs 40908809837, 40909213339). Visual check pending (Mac row in VISUAL_CHECKS.md)
