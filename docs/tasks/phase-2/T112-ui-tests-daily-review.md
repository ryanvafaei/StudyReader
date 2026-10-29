# T112: UI tests, part 1: daily review, actions and the Review settings tab

- **Phase:** 2 (E2.2; ADR-0019: every flow with a clear expected result gets an XCUITest; prepares checkpoint R1)
- **Agent:** ui-builder
- **Depends on:** T109, T110, T111, T106
- **ADRs:** ADR-0011, ADR-0019, ADR-0020, **ADR-0022**
- **Visual check needed:** no (these are the checks; the looks stay on the Mac rows of T106, T109, T110)
- **UI tests:** YES. This task may run its own targeted UI class (criterion 9), max 2 attempts, never in parallel with another CI job: `./scripts/uitest.sh StudyReaderUITests/ReviewSessionTests StudyReaderUITests/LibraryOpenTests`.

## Goal
CI-reliable XCUITests for the daily review flow on the seeded library (T111), including the key rule of ADR-0022 and the HANDOFF Return/Escape rule for the new text fields.

## Files to touch
- `StudyReaderUITests/ReviewSessionTests.swift` (new)
- `StudyReaderUITests/Support/StudyReaderUI+Review.swift` (new: helpers; don't edit the user's existing `Support/` files)
- Product code only to add a missing accessibility identifier named in T109/T110 (say which in the report).

## Interfaces to produce
```swift
extension StudyReaderUI {
    /// Selects the sidebar "Review" section and waits for the start screen or the empty state.
    func showReview(file: StaticString = #filePath, line: UInt = #line)
    func element(_ identifier: String) -> XCUIElement     // app.descendants(matching: .any)[identifier].firstMatch
    var reviewProgress: String { get }                    // text(of: element("review-progress"))
    var reviewFrontText: String { get }                   // text(of: element("review-card-front"))
    func rate(_ identifier: String)                       // clicks e.g. "review-rate-good" and waits for the progress to change
    func pressKey(_ key: String)                          // app.typeKey(key, modifierFlags: [])
}
```

## Rules (same as T88/T89)
- `final class ReviewSessionTests: XCTestCase`, `continueAfterFailure = true`, `@MainActor` on tests and helpers; `StudyReaderUI.launch()` (seeded, fresh settings per launch, T84).
- Seed facts (T111): 8 cards; order "Gradient descent … lowers the loss" first, then Lecture p. 1 ("Proteins embedded in the membrane move materials."), Lecture p. 2 ("Cristae increase the inner membrane surface area.", note "Check this for the quiz"), Probability, then Membrane Transport, "small batch of examples", "too large a step can diverge", Lecture p. 3.
- Wait with `waitForExistence`/`ui.waitUntil` (5–10 s); `ui.settle` only. Attach `ui.attachHierarchy` in the first test and a screenshot of the start screen, a card, the actions bar with the note editor open, and the summary.
- No pixel scans, no drags, no appearance arguments.
- **Constraint (standing rule, HANDOFF.md):** Return and Escape typed in the new review text fields must not open a document, clear the library selection, rate or reveal. `LibraryOpenTests` runs in the same targeted run.

## Tests
1. `testStartScreenShowsTheSeededCounts`: Review shows "8 cards to review" and "4 due · 4 new"; the sidebar Review row shows 8 if the badge is queryable (`ui.attachHierarchy` decides; if the badge isn't exposed, assert only the start screen and say so in the report).
2. `testRatingWithButtonsAndKeys`: Start → progress "1 of 8", front contains "lowers the loss"; click Remembered → "2 of 8", front contains "Proteins embedded"; press "1" → "3 of 8", front contains "Cristae" and the note "Check this for the quiz" is visible; press Space → still "3 of 8" (passive: nothing to reveal); press "3" → still "3 of 8" (two-button mode).
3. `testSkipMovesTheCardToTheEnd`: Start, Skip → progress "1 of 8", front contains "Proteins embedded"; rate seven times with "2" → the last card's front contains "lowers the loss".
4. `testFinishingShowsTheSummaryAndEmptiesToday`: rate all 8 (mix of 1 and 2: four each) → summary "Reviewed 8 cards", "Remembered 50%"; Done → `review-empty` ("Nothing to review").
5. `testKeysInTheNoteFieldDoNotRate` (ADR-0022): Start, open Note, type "12 3" and press Return, wait 1 s → progress still "1 of 8"; the note editor's value contains "12 3"; close the editor, Skip, come back round to the card (or reopen Note) → the text is still there.
6. `testReturnAndEscapeInTheEditFieldDoNothingElse`: in the Library select a card first (so a selection exists), switch to Review, Start, Edit, type "Better wording", press Return, then Escape → progress "1 of 8", no reader tab opened (`tabTitles.isEmpty`), Cancel → front unchanged; Edit again, replace the text, Save → front shows the new text and Show Original appears; Show Original → front shows the original; back in the Library the same card is still selected.
7. `testFrequencyOffRemovesTheCard`: Start; Frequency → Off → progress "1 of 7" and front contains "Proteins embedded".
8. `testOpenInDocumentOpensTheReader`: Start, rate once (Lecture p. 1 is current), Open in Document → a reader tab "Sample · Lecture 1: Cell Biology" appears; back in the library window the session still shows "2 of 8".
9. `testReviewSettingsTab`: ⌘, → toolbar button "Review" exists; "Daily limit" stepper, "New cards per day", "Show four rating buttons" and a "Frequency for Lecture slides" picker exist; turn on four buttons, close Settings, Review → Start → four rating buttons (`review-rate-again` … `review-rate-easy`) exist.

## Acceptance criteria
1. The nine tests above exist and follow the rules.
2. The targeted run (`./scripts/uitest.sh StudyReaderUITests/ReviewSessionTests StudyReaderUITests/LibraryOpenTests`, at most 2 attempts) passes, or the report lists each remaining failure with its CI message and hierarchy attachment. A test that fails because the product misses the spec keeps its failing assertion (ADR-0019) and is reported as a spec FAIL; never weaken it to pass.
3. `./scripts/build.sh` succeeds.

## Out of scope
- Mastery, themed reviews and flashcards (T128). Dark mode, restart persistence, reminder (Mac rows).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
