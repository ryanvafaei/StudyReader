# T118: Mastery in the Highlights browser; bulk "Create Review Cards"

- **Phase:** 2 (E2.3 Mastery; SPEC F-13 Mastery filter and detail "Mastery (F-16)", F-16 badge, F-17 bulk action)
- **Agent:** ui-builder
- **Depends on:** T116, T117
- **ADRs:** **ADR-0021**
- **Visual check needed:** yes (Mac row below)
- **UI tests:** none in this task; T128 covers it. Verify with `./scripts/build.sh` and the filter in criterion 5.

## Goal
In the Highlights browser: a "Mastery" badge on rows, the Mastery filter, a "Mastery…" button in the detail pane that opens the editor (T117), and the bulk action "Create Review Cards" for selected highlights that have none. The reader popover's entry point is T119.

## Files to touch
- `StudyReader/Features/HighlightsBrowser/HighlightsBrowserModel.swift` (modify: Mastery filter, `createReviewCards()`, editor request)
- `StudyReader/Features/HighlightsBrowser/HighlightsBrowserView.swift` (modify: row badge, filter menu, bulk button, sheet, alert)
- `StudyReader/Features/HighlightsBrowser/HighlightDetailView.swift` (modify: badge, "Mastery…" button)
- `StudyReader/Resources/Localizable.xcstrings` (modify: plural "Created %lld review cards")
- `StudyReaderTests/HighlightsBrowserTests/HighlightsBrowserModelTests.swift` (modify: add tests)

## Interfaces to produce
```swift
// HighlightsBrowserModel
var masteryFilter: Bool? { get set }       // forwards to filter.hasMastery (T116)
var canCreateReviewCards: Bool { get }     // any selected item has reviewCardCount == 0
/// Selected rows with reviewCardCount == 0 get a passive card (ReviewCardFactory.passive at environment.now(),
/// reviewCardRepository.insertPassiveCards). bulkMessage = "Created N review cards" (plural catalog entry), or
/// "The selected highlights already have review cards." when none qualifies. Errors → errorMessage
/// "The review cards couldn't be created."
func createReviewCards() async
private(set) var bulkMessage: String?
func dismissBulkMessage()
/// Highlight id the browser shows the Mastery editor for (sheet over the browser).
var masteryHighlightId: String?
```

## What to do
1. **Rows:** a small "Mastery" capsule (accessibility label "Has Mastery cards") when `item.masteryCardCount > 0`.
2. **Filter bar:** a "Mastery" menu (accessibility label "Filter by Mastery"): Any, With Mastery, Without Mastery (`masteryFilter` nil / true / false), checkmark on the current choice. "Clear" already resets the whole `filter`.
3. **Detail pane:** the capsule and a "Mastery…" button (`Label("Mastery…", systemImage: "brain")`, accessibility label "Mastery") → `model.masteryHighlightId = item.id`. `HighlightsBrowserView` presents `MasteryEditorSheet(highlightId:session:)` with `.sheet(item:)` over a small `Identifiable` wrapper; dismissing sets it to nil.
4. **Bulk bar:** "Create Review Cards" (enabled when `canCreateReviewCards`) → `await model.createReviewCards()`; `bulkMessage` in an alert with OK, like the export message.
5. Keep every existing accessibility label and identifier (Phase 1 UI tests rely on them). The bulk bar already wraps at 1024 pt (BACKLOG B36); don't try to fix that here, but check the new button doesn't push "Delete…" out of the window in the T128 screenshot.

## Constraint (HANDOFF standing rule, Library Return/Escape)
This task adds no text field itself (the editor's fields are T117's). The sheet it presents belongs to the main window: `LibraryView` stays unmounted in the Highlights section (T69). T128 covers Return/Escape in the sheet (`MasteryEditorTests/testReturnAndEscapeStayInTheSheet`).

## Acceptance criteria
1. `HighlightsBrowserModelTests/masteryFilter`: three highlights (none, passive, passive + cloze): `masteryFilter = true` → one row, `false` → two, nil → three (bounded wait as in the other filter tests).
2. `HighlightsBrowserModelTests/createReviewCardsForSelection` (SPEC F-17 bulk): select two highlights without cards and one with a passive card → two cards created, `bulkMessage == "Created 2 review cards"`; again → "The selected highlights already have review cards."; `canCreateReviewCards` is false then.
3. `HighlightsBrowserModelTests/createdCardsRespectAnOffCategory`: a highlight in a category set to off → the created card is suspended (`.frequencyOff`).
4. Existing `HighlightsBrowserModelTests` pass.
5. `./scripts/test.sh StudyReaderTests/HighlightsBrowserModelTests` passes; `./scripts/build.sh` succeeds.
6. Report "Visual check needed: yes" with this Mac row. **T118 Mastery in the browser** (Mac; light and dark): a highlight with Mastery cards shows the "Mastery" capsule; the Mastery filter narrows the list and Clear resets it; the detail pane's "Mastery…" opens the editor over the browser; with Notes' auto-create off, highlight something in a Notes document, select it in the browser, "Create Review Cards" → "Created 1 review card" (singular), and the Review badge grows by one if the new-per-day budget allows it.

## Out of scope
- The editor (T117), the reader popover (T119), flashcards (T127).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
- 2026-10-29, implementer ui-builder sonnet medium (reworks: none), reviewer code-reviewer sonnet medium: APPROVED, spec met (code-verifiable criteria); CI build and full unit tests green, 896 tests (runs 40933920273, 40934278445). Visual check pending (Mac row in VISUAL_CHECKS.md)
