# T128: UI tests, part 2: Mastery, themed reviews, flashcards

- **Phase:** 2 (E2.3–E2.5; ADR-0019; prepares checkpoint R2)
- **Agent:** ui-builder
- **Depends on:** T118, T124, T127 (and T112 for the helpers)
- **ADRs:** ADR-0011, ADR-0019, ADR-0020, **ADR-0022**
- **Visual check needed:** no (the looks stay on the Mac rows of T117–T127)
- **UI tests:** YES. This task may run its own targeted UI classes (criterion 2), max 2 attempts, never in parallel with another CI job: `./scripts/uitest.sh StudyReaderUITests/MasteryEditorTests StudyReaderUITests/ThemedReviewsTests StudyReaderUITests/FlashcardsTests StudyReaderUITests/LibraryOpenTests`.

## Goal
CI-reliable XCUITests for the Mastery editor (from the Highlights browser), themed reviews (create, run, complete, duplicate, delete) and the Flashcards view, plus the HANDOFF Return/Escape rule for every new main-window text field of these tasks.

## Files to touch
- `StudyReaderUITests/MasteryEditorTests.swift`, `StudyReaderUITests/ThemedReviewsTests.swift`, `StudyReaderUITests/FlashcardsTests.swift` (new)
- `StudyReaderUITests/Support/StudyReaderUI+Review.swift` (modify: helpers you need; T112 created it)
- Product code only to add a missing accessibility label or identifier named in T117–T127 (say which in the report).

## Rules
Same as T112 (class pattern, `@MainActor`, seeded launch, bounded waits, one hierarchy attachment per class, screenshots of the Mastery sheet, the themed list, a themed card, the Flashcards list with a selected card). Seed facts: T111 (10 cards, 8 in today's daily plan). The seeded tags are document tags, and themed-review tag filters match highlight tags (as the browser and the export do), so filter themed reviews by category: Lecture slides holds Lecture 1 (p. 1 and p. 2 due, p. 3 new) and Membrane Transport (new), 4 cards. No pixel scans, drags or appearance arguments.
**Constraint (standing rule, HANDOFF.md):** Return and Escape in every new field must stay in that field or its sheet: no reader tab opens, the library selection is unchanged. `LibraryOpenTests` runs in the same targeted run.

## Tests
**MasteryEditorTests**
1. `testCreateQuestionCardFromTheBrowser`: Highlights → select the "Cristae" row → detail "Mastery…" → the sheet opens; "Add Question"; type "What do cristae do?" in Question; Save → the sheet closes and the row shows "Has Mastery cards"; the Mastery filter "With Mastery" shows exactly 1 highlight.
2. `testMasteryCardJoinsTodaysReview`: after test 1's steps, Review → the start screen shows "3 due · 5 new" (the Cristae passive card is suspended; the new Q&A card is the fifth new card); Start → rate twice with "2" → the third card is Probability, not Cristae.
3. `testReturnAndEscapeStayInTheSheet`: select a library card first; Highlights → a row → Mastery… → Add Question → press Return in Question → the sheet is still open, no reader tab; press Escape → the sheet closes, nothing saved (the row has no Mastery capsule), the library selection is unchanged.

**ThemedReviewsTests**
4. `testCreateRunAndCompleteAThemedReview`: Themed Reviews → empty state → New Themed Review… → name "Exam", category "Lecture slides", cards per session 5 → Save → the row shows "Every day", "Never done" and "Due"; Run → progress "1 of 4"; rate all with "2" → summary "Reviewed 4 cards"; Done → the list, "Due" gone.
5. `testDuplicateAndDelete`: create "Exam" (minimal), Duplicate → "Exam copy"; Delete… "Exam copy" → confirm → one row left.
6. `testReturnAndEscapeInTheEditorStayInTheSheet`: select a library card first; New Themed Review… → Escape → no sheet, no row; New… again → type "Quiz" → Return → saved (default action), one row; no reader tab opened; the library selection is unchanged.
7. `testThemedRatingsLeaveTheDailyReview`: create and run "Exam" (category Lecture slides, 5 cards, due first). Its cards are Lecture p. 1, Lecture p. 2 (due), then Membrane Transport and Lecture p. 3 (never reviewed, oldest first). Rate all four with "2"; Review → "4 cards to review" and "2 due · 2 new" ("lowers the loss" and Probability; "small batch of examples" and "too large a step can diverge": the two cards introduced in the themed session count against today's 5 new).

**FlashcardsTests**
8. `testFlashcardsListAndFilters`: Review → "Flashcards" → "10 cards"; State "New" → "4 cards"; Clear → "10 cards".
9. `testFrequencyOffShowsSuspended`: select a card → Frequency Off → its row shows "Suspended"; State "Suspended" → "1 card".
10. `testReturnAndEscapeInTheNoteFieldDoNothingElse`: select a library card first; Flashcards → select a card → Note → type "abc", Return, Escape → the note editor still contains "abc" plus a line break; no reader tab; switch to Daily Review and back: the selection is kept; the library selection is unchanged.

## Acceptance criteria
1. The ten tests exist and follow the rules.
2. The targeted run passes in at most 2 attempts, or the report lists each remaining failure with its CI message and hierarchy attachment; spec failures keep their assertion and are reported as spec FAILs (ADR-0019).
3. `./scripts/build.sh` succeeds.

## Out of scope
- The reader popover's Mastery button (Mac row T119), dark mode, reminder.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
