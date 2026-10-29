# T116: Browse query: Mastery filter and review-card counts

- **Phase:** 2 (E2.3; SPEC F-13 "Mastery status" filter, F-16 "Mastery" badge, F-17 bulk "Create review cards" for highlights that have none)
- **Agent:** data-layer
- **Depends on:** T114
- **ADRs:** ADR-0012
- **Visual check needed:** no
- **UI tests:** none. Verify with `./scripts/build.sh` and the filter in criterion 5.

## Goal
The highlights browser query learns a Mastery filter and returns two counts per row (Mastery cards, all review cards), so the browser can show the "Mastery" badge, filter on it and enable "Create Review Cards" only for rows without a card.

## Files to touch
- `StudyReader/Core/Repositories/HighlightBrowseQuery.swift` (modify)
- `StudyReaderTests/CoreTests/HighlightBrowseQueryTests.swift` (modify: add tests)

## Interfaces to produce
```swift
struct HighlightBrowserFilter {
    // add, after `views`:
    /// true: the highlight has at least one cloze or qa card; false: none; nil: either.
    var hasMastery: Bool? = nil
}
struct HighlightListItem {
    // add, with defaults so every existing memberwise call still compiles:
    var masteryCardCount: Int = 0     // cloze + qa cards of this highlight
    var reviewCardCount: Int = 0      // all review cards (passive included)
}
```
- In `HighlightBrowseSQL.items`, select the two counts as correlated subqueries (`(SELECT COUNT(*) FROM reviewCard r WHERE r.highlightId = h.id AND r.cardType IN ('cloze','qa')) AS masteryCardCount`, and the same without the type condition) and read them per row. The `reviewCard_highlight` index covers both.
- In `conditions(for:onlyIds:)`, `hasMastery` adds `EXISTS (SELECT 1 FROM reviewCard r WHERE r.highlightId = h.id AND r.cardType IN ('cloze','qa'))` or `NOT EXISTS (…)`.
- The export (`ExportRepository`) and the observation keep working unchanged: they call the same function.

## Acceptance criteria
Tests use an in-memory database, `TestData` records, cards from `ReviewCardFactory`, and end with `FTSIntegrity.check`.
1. `HighlightBrowseQueryTests/masteryFilter`: three highlights (none, passive only, passive + qa): `hasMastery == true` → only the third; `false` → the first two; nil → all three; combined with a colour filter it ANDs.
2. `HighlightBrowseQueryTests/cardCounts`: the rows carry `masteryCardCount` 0, 0, 1 and `reviewCardCount` 0, 1, 2.
3. `HighlightBrowseQueryTests/observeBrowseSeesNewCards`: `observeBrowse` emits a row with `reviewCardCount == 1` after `insertPassiveCards` (`TestWait.until`, `#expect`).
4. Existing `HighlightBrowseQueryTests`, `HighlightsBrowserModelTests`, `ExportRepositoryTests` and `ExportRendererTests` pass unchanged.
5. `./scripts/test.sh StudyReaderTests/HighlightBrowseQueryTests StudyReaderTests/HighlightsBrowserModelTests StudyReaderTests/ExportRepositoryTests StudyReaderTests/ExportRendererTests` passes; `./scripts/build.sh` succeeds.

## Out of scope
- The browser UI (T118).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
- 2026-10-29, implementer data-layer haiku medium (reworks: none), reviewer code-reviewer sonnet medium: APPROVED, spec met; CI build and full unit tests green, 887 tests (runs 40928976647, 40929347040)
