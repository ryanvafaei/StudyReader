# T109: Review screen: start, card, reveal, rating, summary; sidebar badge

- **Phase:** 2 (E2.2 Daily review; SPEC F-15, F-01 sidebar "Review", §5 shortcuts Space and 1–2/1–4)
- **Agent:** ui-builder
- **Depends on:** T108
- **ADRs:** **ADR-0022** (keys only through the focused card), ADR-0017 (Open in Document comes in T110)
- **Visual check needed:** yes (Mac row below)
- **UI tests:** none in this task; T112 covers the flow. Verify with `./scripts/build.sh` and the filter in criterion 6.

## Goal
Sidebar "Review" shows today's daily review: a start screen with the counts, then one card at a time with reveal and rating buttons (and keys), then the summary. The Review row shows the due count as a badge. The card actions bar (note, edit, frequency, open, skip) is T110.

## Files to touch
- `StudyReader/Features/Review/ReviewSectionView.swift` (new: hosts `session.dailyReviewModel()`)
- `StudyReader/Features/Review/ReviewSessionView.swift` (new: renders a `ReviewSessionModel` by phase; reused by themed sessions in T124)
- `StudyReader/Features/Review/ReviewCardView.swift` (new)
- `StudyReader/Features/Review/ReviewSummaryView.swift` (new)
- `StudyReader/Features/Review/ReviewStrings.swift` (new: the plural texts below)
- `StudyReader/App/RootView.swift` (modify: `.review` route, Review row badge, badge observation)
- `StudyReader/Resources/Localizable.xcstrings` (modify: plural variations for the two count strings, same shape as T52g/T69)
- `StudyReaderTests/ReviewTests/ReviewStringsTests.swift` (new)

## Interfaces to produce
```swift
enum ReviewStrings {
    /// "1 card to review" / "N cards to review" (one catalog entry with plural variations).
    nonisolated static func cardsToReview(_ count: Int) -> String
    /// "Reviewed 1 card" / "Reviewed N cards".
    nonisolated static func reviewed(_ count: Int) -> String
    /// "N due · M new" (no plural needed: the numbers stand alone).
    nonisolated static func dueAndNew(due: Int, new: Int) -> String
}
struct ReviewSessionView: View {
    /// onDone nil: the summary's Done calls model.endSession() then loadPlan() (daily). T124 passes its own closure.
    init(model: ReviewSessionModel, session: AppSession, onDone: (() -> Void)? = nil)
}
```

## What to do
1. **Route.** In `RootView`, `model.selection == .review` → `ReviewSectionView(session: session)`. It replaces the detail column like the other sections, so `LibraryView` (with its hidden Return/Escape buttons) is not in the hierarchy. Keep that.
2. **Badge.** In the sidebar `List`, the Review row gets `.badge(session.reviewBadge.dailyDueCount)` (0 shows no badge). Start the observation in `RootView` with `.task(id: session.settings.dailyLimits) { await session.reviewBadge.observe() }` so a limit change restarts it.
3. **`ReviewSectionView`**: `let model = session.dailyReviewModel()`; on appear (`.task`) call `await model.loadPlan()` when the phase is `.idle`, `.ready` or `.failed` (so the counts are fresh), never while `.reviewing` or `.finished` (a running session or its summary survives leaving the section); shows `ReviewSessionView(model:session:)`.
4. **`ReviewSessionView`** by `model.phase`:
   - `.idle`: `ProgressView()`.
   - `.ready(due, new)` with due + new > 0: title "Daily Review", `ReviewStrings.cardsToReview(due + new)`, `ReviewStrings.dueAndNew`, button "Start Review" (`.borderedProminent`, identifier `review-start`). With 0: `ContentUnavailableView("Nothing to review", systemImage: "checkmark.circle", description: Text("You're done for today. New cards come back after 4:00."))`, identifier `review-empty`.
   - `.reviewing`: `ReviewCardView`.
   - `.finished(summary)`: `ReviewSummaryView`.
   - `.failed(message)`: the message and "Try Again" (`loadPlan()`).
   - `model.errorMessage`, when set, as a red caption under the card.
5. **`ReviewCardView`** (centred column, max width ~640, scrolls when long):
   - Header: document title (identifier `review-document-title`), "p. N" when `pageNumber` is set, a colour dot with `session.settings.label(for: content.color)`, and `model.progressText` (identifier `review-progress`) at the trailing edge.
   - Front: `.markdown` → `RichTextView(markdown)` (identifier `review-card-front`); `.image` → the PNG via `session.environment.fileStore.url(forRelativePath:)`, loaded once in `.task(id: path)` into `@State` (never read files in `body`, B15), `scaledToFit`, max height 360, accessibility label "Snapshot".
   - Passive cards: note (`NoteMarkdownView`, only when not empty) and tag chips (`#name`) below the front at once.
   - Mastery cards before reveal: button "Show Answer" with a "Space" hint (identifier `review-reveal`). After reveal: a divider, `back` (identifier `review-card-back`), `source` when set, then note and tags.
   - Rating row: one button per `model.ratingButtons`, title plus its key as a small secondary hint ("1"), identifiers `review-rate-again`, `review-rate-hard`, `review-rate-good`, `review-rate-easy` (by rating), disabled unless `model.canRate`. Plain buttons: **no `.keyboardShortcut`** on them (ADR-0022).
   - Keys: the card's outer container is `.focusable()`, `.focusEffectDisabled()`, bound to a `@FocusState`, focused on appear and after every card change (`.onChange(of: model.current?.id)`). `.onKeyPress(characters: CharacterSet(charactersIn: " 1234"), phases: .down)`: `if let action = model.action(forKey: Character(press.characters)) { Task { await model.perform(action) }; return .handled }; return .ignored`.
6. **`ReviewSummaryView`**: "Session complete", `ReviewStrings.reviewed(summary.reviewed)` (identifier `review-summary-reviewed`), "Remembered \(rememberedPercent)%" (identifier `review-summary-remembered`), "Due tomorrow: \(dueTomorrow)" (identifier `review-summary-tomorrow`), button "Done" (identifier `review-done`) → `onDone` when given, else `model.endSession()` then `await model.loadPlan()`.
7. Every count string through `ReviewStrings` and the catalog; other strings `String(localized:)`/`Text("…")`.

**Constraint (HANDOFF standing rule, Library Return/Escape):** this task adds no text field. Return and Escape on the review screen do nothing special (no `.defaultAction`/`.cancelAction` shortcuts here). T110 adds the text fields and their rule.

## Acceptance criteria
1. `ReviewStringsTests/pluralCounts`: `cardsToReview(1) == "1 card to review"`, `cardsToReview(8) == "8 cards to review"`, `reviewed(1) == "Reviewed 1 card"`, `reviewed(3) == "Reviewed 3 cards"`, `dueAndNew(due: 4, new: 4) == "4 due · 4 new"`.
2. Reviewer: no `.keyboardShortcut` without modifiers in `Features/Review/`; no file read in a `body`; `LibraryView` is not mounted while Review is shown.
3. Existing `RootModelTests`, `AppSessionTests` pass.
4. `./scripts/build.sh` succeeds (the views compile with the T108 interfaces unchanged; report any interface you had to add).
5. Report "Visual check needed: yes" with this Mac row. **T109 Review screen** (Seed Sample Library after T111, light and dark): sidebar Review shows a badge with the due count; the section shows "N cards to review" and "N due · M new"; Start Review shows the first card with title, page, colour label and "1 of N"; passive cards show the note and tags at once, keys 1 and 2 rate, Space does nothing; on a Mastery card (after T117) Space reveals, 1/2 then rate; after the last card the summary shows reviewed count, remembered %, due tomorrow; Done shows "Nothing to review"; with "Show four rating buttons" on, four buttons and keys 1–4; a snapshot highlight shows its image; with the search field focused, typing 1 or 2 doesn't rate; quit and relaunch mid-session: the rated cards stay rated and the rest come back (SPEC F-15 AC3).
6. `./scripts/test.sh StudyReaderTests/ReviewStringsTests StudyReaderTests/RootModelTests StudyReaderTests/AppSessionTests` passes.

## Out of scope
- The actions bar (T110), themed sessions (T124), the flashcards switch (T127).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
- 2026-10-29, implementer ui-builder sonnet medium (reworks: none), reviewer code-reviewer sonnet medium: APPROVED, spec met (code-verifiable criteria); CI build and full unit tests green, 863 tests (runs 40903436002, 40903999800). Visual check pending (Mac row in VISUAL_CHECKS.md)
