# T124: Themed Reviews section: list, run, duplicate, delete, badge

- **Phase:** 2 (E2.4 Themed reviews; SPEC F-20, F-01 sidebar "Themed Reviews")
- **Agent:** ui-builder
- **Depends on:** T122, T123, T109 (`ReviewSessionView`), T110
- **ADRs:** **ADR-0022**
- **Visual check needed:** yes (Mac row below)
- **UI tests:** none in this task; T128 covers it. Verify with `./scripts/build.sh` and the filter in criterion 5.

## Goal
Sidebar "Themed Reviews" lists the user's themed reviews with their schedule and a "Due" marker, lets the user create, edit, duplicate and delete them, and runs one with the same review screen as the daily review. The sidebar row shows how many are due.

## Files to touch
- `StudyReader/Features/Review/Themed/ThemedReviewsModel.swift` (new)
- `StudyReader/Features/Review/Themed/ThemedReviewsView.swift` (new)
- `StudyReader/App/RootView.swift` (modify: `.themedReviews` route, badge, `observeThemed()` task)
- `StudyReader/Resources/Localizable.xcstrings` (modify: "Every %lld days" plural)
- `StudyReaderTests/ReviewTests/ThemedReviewsModelTests.swift` (new)

## Interfaces to produce
```swift
@MainActor @Observable
final class ThemedReviewsModel {
    init(session: AppSession, calendar: Calendar = .current)
    private(set) var reviews: [ThemedReview] = []
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    var selection: String?                            // selected review id
    var editorRequest: ThemedEditorRequest?           // drives the T123 sheet
    /// The running session, if any. While non-nil the section shows the session instead of the list.
    private(set) var runningSession: ReviewSessionModel?

    func observe() async                              // themedReviewRepository.observeAll()
    func isDue(_ review: ThemedReview) -> Bool        // ThemedReviewSchedule.isDue(review, now: environment.now(), calendar:)
    /// "Every day" (daily, or every 1 day), "Every N days" (N ≥ 2), "Mon, Thu" (short weekday symbols in the calendar's order).
    func intervalSummary(_ review: ThemedReview) -> String
    func newReview()                                  // editorRequest = .new
    func edit(_ id: String)                           // editorRequest = .edit(id)
    func duplicate(_ id: String) async                // repository.duplicate(at: now); selects the copy
    func delete(_ id: String) async                   // repository.delete; clears the selection
    func run(_ id: String) async                      // runningSession = ReviewSessionModel(session:, context: .themed(id:)); loadPlan()
    func stopRunning()                                // runningSession = nil (an unfinished session stays uncompleted)
}
enum ThemedEditorRequest: Identifiable, Equatable {
    case new
    case edit(String)
    var id: String { get }      // "new" / the review id
    var reviewId: String? { get }
}
```

## What to do
1. **Route and badge.** `RootView`: `.themedReviews` → `ThemedReviewsView(session:)`; the Themed Reviews row gets `.badge(session.reviewBadge.themedDueCount)`; start `session.reviewBadge.observeThemed()` in a `.task` next to the daily badge task.
2. **List** (when `runningSession == nil`): toolbar-style header "Themed Reviews" with "New Themed Review…" (`plus`, accessibility label "New Themed Review"). Rows: name, `intervalSummary`, "Last done <date>" or "Never done", a "Due" capsule when `isDue` (accessibility label "Due"), and a "Run" button (accessibility label "Run <name>"). Double-click or Return on a selected row runs it: use `.contextMenu(forSelectionType:primaryAction:)` on the `List`, so Return is the list's primary action, not a window-wide key equivalent. Context menu: Run, Edit…, Duplicate, Delete… (confirmation "Delete “<name>”?" — "The review cards stay; only this themed review is removed."). Empty state: `ContentUnavailableView("No themed reviews", systemImage: "calendar.badge.clock", description: Text("Create one to review a chosen set of highlights, for example before an exam."))` with "New Themed Review…".
3. **Editor:** `.sheet(item: $model.editorRequest)` → `ThemedReviewEditorSheet` (T123) with the request's id.
4. **Running:** `ReviewSessionView(model: running, session:)` (T109) with a header "← Themed Reviews" button (`stopRunning()`) and the review's name (`running.themedReviewName`). The summary's Done returns to the list: pass `onDone: { model.stopRunning() }` (T109's parameter), not a new plan.
5. Errors (`errorMessage`) as a red caption over the list.

## Constraint (HANDOFF standing rule, Library Return/Escape)
`LibraryView` is not mounted while this section shows (RootView replaces the detail column): keep it. The running session's note and edit fields follow T110's rule (keys typed there never rate). Return on a selected list row runs that review (the list's primary action), never opens a library document; Escape does nothing here. T128 proves it.

## Acceptance criteria
`@MainActor`, in-memory session, UTC calendar where dates matter.
1. `ThemedReviewsModelTests/listAndDue`: two reviews (never done; done today) → `reviews` sorted by name, `isDue` true/false.
2. `ThemedReviewsModelTests/intervalSummaries` (table): daily → "Every day"; every 1 day → "Every day"; every 3 days → "Every 3 days" (plural catalog entry `Every %lld days`); weekdays [2, 5] → "Mon, Thu" (build the expected value from the same calendar's `shortWeekdaySymbols`).
3. `ThemedReviewsModelTests/duplicateAndDelete`: duplicate selects the copy; delete removes it and clears the selection.
4. `ThemedReviewsModelTests/runCreatesAThemedSession`: `run(id)` → `runningSession` with context `.themed(id:)` and phase `.ready`; `stopRunning()` → nil, the review not completed.
5. `./scripts/test.sh StudyReaderTests/ThemedReviewsModelTests StudyReaderTests/RootModelTests` passes; `./scripts/build.sh` succeeds.
6. Report "Visual check needed: yes" with this Mac row. **T124 Themed Reviews** (Mac, Seed Sample Library; light and dark): empty state with "New Themed Review…"; create "Exam" over the category Lecture slides (daily, 5 cards) → the row shows "Every day", "Never done", "Due", the sidebar row a badge 1; Run → the review screen with "Exam" in the header and 4 cards; finish → summary; Done → the list shows "Last done <today>" and no "Due", the badge clears; after 04:00 the next day it is due again; Duplicate → "Exam copy"; Delete asks first; Return on a selected row runs it.

## Out of scope
- Exporting a themed review (Phase 1 export sheet already offers the scope).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
- 2026-10-29, implementer ui-builder sonnet medium (reworks: none), reviewer code-reviewer sonnet medium: APPROVED, spec met (code-verifiable criteria); sidebar row structure unchanged (only the badge argument became badgeCount(for:)); CI build and full unit tests green, 929 tests (runs 40953467959, 40953745444). Visual check pending (Mac row in VISUAL_CHECKS.md)
