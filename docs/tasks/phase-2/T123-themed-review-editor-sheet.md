# T123: Themed review editor sheet

- **Phase:** 2 (E2.4 Themed reviews; SPEC F-20 definition: filter, cards per session, interval, order)
- **Agent:** ui-builder
- **Depends on:** T120
- **ADRs:** **ADR-0022**
- **Visual check needed:** yes (Mac row below)
- **UI tests:** none in this task; T128 covers it. Verify with `./scripts/build.sh` and the filter in criterion 6.

## Goal
A sheet to create or edit one themed review: name; filter (tags with Any/All, documents, categories, colours); cards per session (5–100, default 20); interval (every day, every N days, specific weekdays); order (due first then least recently reviewed, or random). The list and Run are T124.

## Files to touch
- `StudyReader/Features/Review/Themed/ThemedReviewEditorModel.swift` (new)
- `StudyReader/Features/Review/Themed/ThemedReviewEditorSheet.swift` (new)
- `StudyReaderTests/ReviewTests/ThemedReviewEditorModelTests.swift` (new)

## Interfaces to produce
```swift
@MainActor @Observable
final class ThemedReviewEditorModel {
    /// reviewId nil = new review (draft starts as ThemedReviewDraft(name: "")); else load() reads it.
    init(reviewId: String?, environment: AppEnvironment)
    var draft: ThemedReviewDraft
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?            // ThemedReviewError text from the last save
    // Lookups for the pickers (live, like HighlightsBrowserModel.observeLookups):
    private(set) var tags: [LibraryTag] = []
    private(set) var documents: [LibraryDocument] = []   // sorted by title
    private(set) var categories: [DocumentCategory] = []
    func load() async
    func observeLookups() async
    func toggle(tagId: String)                         // in draft.filter.tagIds (kept unique, order of adding)
    func toggle(documentId: String)
    func toggle(categoryId: String)
    func toggle(color: HighlightColor)
    func toggle(weekday: Int)                          // 1…7 in draft.interval.weekdays (sorted)
    var intervalKind: ReviewInterval.Kind { get set }  // switching kind keeps n = 1 / weekdays = [today's weekday] defaults
    var everyNDays: Int { get set }                    // 1…365
    var canSave: Bool { get }                          // trimmed name not empty
    /// create (new) or update (existing) through ThemedReviewRepository; true on success; false with errorMessage.
    func save() async -> Bool
}
```

## What to do
1. **Sheet** (width ~520, title "New Themed Review" / "Edit Themed Review"), a `Form`:
   - `TextField("Name", …)` (accessibility label "Themed review name"), placeholder "e.g. ML1 exam week".
   - Section "Highlights": Tags (a menu or popover list with checkmarks, plus a segmented Any/All shown when ≥ 2 tags are chosen), Documents (same), Categories (same), Colours (five toggles with `HighlightPalette.title`). An empty section means "all" (caption: "Leave a group empty to include everything.").
   - Section "Session": `Stepper` "Cards per session: N" (5…100); `Picker` "Order": "Due first, then least recently reviewed" / "Random".
   - Section "Schedule": `Picker` "Repeat": Every day / Every N days / On weekdays; "Every N days" shows a `Stepper` (1…365); "On weekdays" shows seven toggles (short weekday symbols from `Calendar.current`, in the calendar's first-weekday order, stored as Calendar weekday numbers).
   - Error text; "Cancel" (`.cancelAction`), "Save" (`.defaultAction`, disabled unless `canSave`). Save closes on true.
2. The host (T124) presents it with `.sheet(item:)` and passes `reviewId` (nil for New).

## Constraint (HANDOFF standing rule, Library Return/Escape)
The sheet belongs to the main window. `LibraryView` (window-wide Return/Escape buttons) is not mounted in the Themed Reviews section (T124 replaces the detail column): keep it so. Return in the Name field saves the sheet (its default action) or does nothing when Save is disabled; it never opens a document. Escape cancels the sheet and never clears the library selection. T128 proves it (`ThemedReviewsTests/testReturnAndEscapeInTheEditorStayInTheSheet`).

## Acceptance criteria
`@MainActor`, in-memory environment.
1. `ThemedReviewEditorModelTests/newReviewSaves`: name "Exam week", tag "exam" toggled, cards 30, every 3 days, random → `save()` true; the repository has one review with those values.
2. `ThemedReviewEditorModelTests/editLoadsAndUpdates`: an existing review loads into `draft`; changing the name and saving updates it; `lastCompletedAt` unchanged.
3. `ThemedReviewEditorModelTests/togglesAndIntervalKinds`: toggling twice removes; switching to weekdays starts with today's weekday (from the environment clock and `Calendar.current`), toggling another adds it sorted; switching to every N days starts at 1.
4. `ThemedReviewEditorModelTests/errorsShow`: an empty-after-trim name → `canSave == false`; weekdays with none selected → `save()` false and the `.invalidInterval` text.
5. Existing suites unaffected.
6. `./scripts/test.sh StudyReaderTests/ThemedReviewEditorModelTests` passes; `./scripts/build.sh` succeeds.
7. Report "Visual check needed: yes" with this Mac row. **T123 Themed review editor** (Mac, light and dark): every control fits the sheet at 520 pt; the tag/document/category pickers show checkmarks; Any/All appears with two tags; the weekday toggles start on the system's first weekday; Save is disabled with an empty name; Return in the name saves; Escape cancels.

## Out of scope
- The list, Run, Duplicate, Delete and the badge (T124).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
