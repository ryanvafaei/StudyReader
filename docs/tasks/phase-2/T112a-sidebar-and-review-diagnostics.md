# T112a: Make the Review UI-test failure visible (navigation titles, sidebar identifiers, diagnostic helpers)

- **Phase:** 2 (unblocks T112 and T128; user decision 2026-10-29)
- **Agent:** ui-builder
- **Depends on:** T109, T124; the T112 tests live on the branch `wip/T112-ui-tests`
- **Visual check needed:** no
- **UI tests:** YES, up to 3 UI runs in total for the diagnosis (see "Then"), never in parallel with another CI job.

## Why
All nine T112 tests failed at `showReview()`: after clicking the sidebar "Review" row, neither the start screen nor the empty state was found, and the window title stayed "Library". Reading the code shows `ReviewSectionView` and `ThemedReviewsView` have no `.navigationTitle` (Library, Highlights, Tags, Categories do), so the title staying "Library" proves nothing about whether the click worked. The tests need to report what they actually see.

## What to do
1. **Product (a).** Add `.navigationTitle("Review")` to `ReviewSectionView` and `.navigationTitle("Themed Reviews")` to `ThemedReviewsView`, like every other section.
2. **Identifiers (b).** In `RootView`'s sidebar add `.accessibilityIdentifier("sidebar-\(item.rawValue)")` to the `Label` (keep the existing `Label(...).tag(item).badge(...)` structure; touch nothing else in the row). In `ReviewSessionView` add `.accessibilityIdentifier("review-loading")` to the `.idle` `ProgressView`.
3. **Helpers (c).** On the branch `wip/T112-ui-tests` the T112 tests are in `StudyReaderUITests/ReviewSessionTests.swift` and `StudyReaderUITests/Support/StudyReaderUI+Review.swift` (do NOT edit the user's other `Support/` files; if you need a generic `showSection(identifier:)`, put it in `StudyReaderUI+Review.swift`). Restore them into the working tree with `git checkout wip/T112-ui-tests -- StudyReaderUITests/ReviewSessionTests.swift StudyReaderUITests/Support/StudyReaderUI+Review.swift`. Then:
   - `showSection` selects the sidebar row by identifier (`sidebar-review` etc.) and asserts the row is selected (selected state / `isSelected`; use whatever XCUI exposes for an outline row, and say what it exposes).
   - `showReview()` waits for ONE of `review-start`, `review-empty`, `review-retry` or `review-loading` (bounded, 10 s). When it times out it attaches the hierarchy, a screenshot, and a text note saying which of the four it saw (or none), and the selected state of the sidebar row; then fails with that message.
4. Unit/UI verification: `./scripts/build.sh` must pass; no new unit tests are required.

## Then (diagnosis, up to 3 UI runs in total)
Run `./scripts/uitest.sh StudyReaderUITests/ReviewSessionTests` once and read the result:
- **Row not selected** → it is the click: select via keyboard (click Library, then Down arrow to Review) in `showSection`, run again.
- **`review-loading` stuck, or `review-retry`** → product bug in `loadPlan` on the seeded library: do NOT fix it here; report it exactly (hierarchy, message) so it becomes its own task.
- **`review-start` shows** → the tests continue as written; report every remaining test result.
If it is still unclear after 3 UI runs, stop and report the evidence: T112 then goes on the "Needs a Mac" list and T128 continues.

## Acceptance criteria
1. The two titles and the identifiers exist; the sidebar row structure is otherwise unchanged.
2. The helpers report which of the four states was seen when `showReview()` fails.
3. `./scripts/build.sh` passes; the UI-run results are reported with run URLs and the evidence above.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
- 2026-10-29, implementer ui-builder sonnet medium (reworks: none), reviewer code-reviewer sonnet medium: APPROVED (four one-line product edits: navigation titles, sidebar and review-loading identifiers); CI build and full unit tests green, 941 tests (runs 40968849182, 40969211038). 3 UI diagnosis runs: cause not found; T112 on the Needs-a-Mac list, tests kept on branch wip/T112-ui-tests
