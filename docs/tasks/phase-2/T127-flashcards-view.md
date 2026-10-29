# T127: Flashcards view inside Review

- **Phase:** 2 (E2.5 Flashcards view; SPEC F-17 "Flashcards view inside Review", F-18 in the flashcards view)
- **Agent:** ui-builder
- **Depends on:** T126, T117 (Mastery editor), T110 (action patterns), T109
- **ADRs:** **ADR-0022**
- **Visual check needed:** yes (Mac row below)
- **UI tests:** none in this task; T128 covers it. Verify with `./scripts/build.sh` and the filter in criterion 4.

## Goal
The Review section gets a switch between "Daily Review" and "Flashcards". Flashcards lists every card (passive and Mastery) with the F-17 filters, previews the selected card (front and back) and offers the card actions: frequency, note, edit highlight, show original, open in document, edit Mastery cards.

## Files to touch
- `StudyReader/Features/Review/Flashcards/FlashcardsView.swift` (new: filter bar, list, detail)
- `StudyReader/Features/Review/ReviewSectionView.swift` (modify: the segmented switch)
- `StudyReader/App/AppSession.swift` (modify: keep the Review section's mode and the `FlashcardsModel` for the app run, like `dailyReviewModel()`)
- `StudyReader/Resources/Localizable.xcstrings` (modify: "%lld cards" plural from `FlashcardsModel.countText`)

## Interfaces to produce
```swift
// AppSession
enum ReviewSectionMode: String, Sendable { case daily, flashcards }
var reviewSectionMode: ReviewSectionMode = .daily
func flashcardsModel() -> FlashcardsModel          // created once, kept (not persisted)
```

## What to do
1. **Switch:** at the top of `ReviewSectionView`, `Picker` with `.segmented` style: "Daily Review" / "Flashcards" (accessibility label "Review mode"), bound to `session.reviewSectionMode`. Daily shows the T109 screen unchanged.
2. **Filter bar** (same look as the Highlights browser): Document, Category, Tag (+ Any/All), State (New, Learning, Review, Suspended toggles), Type (Passive, Cloze, Question), Due date range (two optional `DatePicker`s), "Clear", and the count `FlashcardsModel.countText(items.count)` (accessibility label "Card count").
3. **List:** rows with a type badge ("Passive", "Cloze", "Q&A"), the front preview (`RichTextView`, 2 lines; snapshot thumbnail for images, loaded once outside `body`), document title, state ("New", "Learning", "Review", "Suspended") and due date (`.dateTime.day().month().year()`). Single selection. Empty states: "No cards yet" / "No cards match these filters" + Clear.
4. **Detail** (one selected card): front, then back and source always shown (it's a preview, not a session), note (`NoteMarkdownView`) and tags; actions: Frequency menu (same as T110), Note (inline `NoteEditorModel`), Edit (inline `ReviewEditDraft`, text highlights only), Show Original (when edited), Open in Document (`session.router.open(… .highlight(id) …)`), and "Edit Mastery Cards…" (opens `MasteryEditorSheet` for the highlight, `.sheet(item:)`). No rating buttons and no Skip (ADR-0022, README Q3). Reuse T110's subviews where they fit; if reuse would need a large refactor of `ReviewActionsBar`, write the few buttons here and say so in the report.
5. Start `observe()` with `.task(id: model.filter)` and `observeLookups()` with `.task`.

## Constraint (HANDOFF standing rule, Library Return/Escape)
The Flashcards detail adds text fields (note editor, edit editor) to the main window, and the Mastery sheet opens over it. `LibraryView` is not mounted while the Review section shows (RootView replaces the detail column): keep it. Return and Escape in these fields must not open a document or change the library selection, and there are no rating keys here. T128 proves it (`FlashcardsTests/testReturnAndEscapeInTheNoteFieldDoNothingElse`).

## Acceptance criteria
1. Reviewer: no `.keyboardShortcut` without modifiers; no file read in `body`; the daily review screen is unchanged when the switch is on "Daily Review"; switching modes and running a search keep the selected flashcard and filters (they live in the kept `FlashcardsModel`).
2. Existing `AppSessionTests`, `ReviewSessionModelTests` pass; add `AppSessionTests/flashcardsModelIsKept` (`session.flashcardsModel() === session.flashcardsModel()`, default mode `.daily`).
3. `./scripts/build.sh` succeeds.
4. `./scripts/test.sh StudyReaderTests/AppSessionTests StudyReaderTests/FlashcardsModelTests` passes.
5. Report "Visual check needed: yes" with this Mac row. **T127 Flashcards** (Mac, Seed Sample Library; light and dark): Review → Flashcards lists 10 cards with type, state and due date; each filter narrows the list and the count follows; select a card → the preview shows front and back; Frequency Off → the row shows "Suspended" and the Suspended filter finds it; Edit and Show Original work; Edit Mastery Cards… opens the editor and a new Q&A card appears in the list; Open in Document opens the reader; switch to Daily Review and back: the selection and filters are kept; narrow window: nothing truncated badly.

## Out of scope
- Rating from this view (README Q3).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
