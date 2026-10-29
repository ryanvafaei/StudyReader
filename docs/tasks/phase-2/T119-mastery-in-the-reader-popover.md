# T119: Mastery in the reader's highlight popover

- **Phase:** 2 (E2.3 Mastery; SPEC F-06 popover action "Mastery…", F-16 badge "Mastery" in the popover)
- **Agent:** ui-builder
- **Depends on:** T117, T118 (same capsule look)
- **ADRs:** ADR-0017 (reader windows), **ADR-0021**
- **Visual check needed:** yes (Mac row below)
- **UI tests:** none (popover UI tests are on the Mac list, BACKLOG B17). Verify with `./scripts/build.sh` and the filter in criterion 4.

## Goal
The popover of a highlight in the reader shows a "Mastery" capsule when the highlight has Mastery cards and a "Mastery…" button that closes the popover and opens the Mastery editor (T117) as a sheet on the reader window.

## Files to touch
- `StudyReader/Features/Annotations/HighlightPopoverModel.swift` (modify: live `masteryCardCount`)
- `StudyReader/Features/Annotations/HighlightPopoverView.swift` (modify: capsule, button)
- `StudyReader/Features/Reader/ReaderModel.swift` (modify: `masteryHighlightId`, `showMastery(highlightId:)`)
- `StudyReader/Features/Reader/ReaderWindowView.swift` (modify: `.sheet(item:)` for the editor; pass the action to the popover)
- `StudyReaderTests/AnnotationsTests/HighlightPopoverModelTests.swift`, `StudyReaderTests/ReaderTests/ReaderModelTests.swift` (modify: one test each)

## Interfaces to produce
```swift
// HighlightPopoverModel
private(set) var masteryCardCount = 0      // cloze + qa cards, from reviewCardRepository.observeCards(forHighlight:)
                                           // inside the existing observe() (run both streams concurrently)
// ReaderModel
var masteryHighlightId: String?            // non-nil: the reader window shows the Mastery editor for it
func showMastery(highlightId: String)      // popoverRequest = nil, then masteryHighlightId = highlightId

// HighlightPopoverView: one new closure parameter, defaulting to a no-op so other call sites still compile
init(request: HighlightPopoverRequest, session: AppSession, onClose: @escaping () -> Void,
     onMastery: @escaping (String) -> Void = { _ in })
```

## What to do
1. Popover: next to the colour dots, the "Mastery" capsule (accessibility label "Has Mastery cards", same look as T118's) when `masteryCardCount > 0`. In the button row between Copy and Delete: "Mastery…" (`Label("Mastery…", systemImage: "brain")`, accessibility label "Mastery") → `onMastery(highlightId)`. Hidden while the highlight is gone.
2. `ReaderWindowView` passes `onMastery: { readerModel.showMastery(highlightId: $0) }` and presents `MasteryEditorSheet(highlightId:session:)` with `.sheet(item:)` over an `Identifiable` wrapper of `masteryHighlightId`; dismissing sets it to nil.
3. The note flush on popover close (`onDisappear`) stays as it is, so a note typed just before "Mastery…" is saved.
4. Showing the popover already ends the auto-highlight undo window (T91); nothing changes there.

**Constraint (HANDOFF standing rule):** not triggered: the reader window isn't the main (library) window.

## Acceptance criteria
1. `HighlightPopoverModelTests/masteryBadgeFollowsCards`: `masteryCardCount` 0, then 1 after `environment.masteryService.save` of a qa draft (`TestWait.until`, `#expect`).
2. `ReaderModelTests/showMasteryClosesThePopover`: after `showPopover(…)`, `showMastery(highlightId:)` → `popoverRequest == nil`, `masteryHighlightId == id`.
3. Existing `HighlightPopoverModelTests` and `ReaderModelTests` pass.
4. `./scripts/test.sh StudyReaderTests/HighlightPopoverModelTests StudyReaderTests/ReaderModelTests` passes; `./scripts/build.sh` succeeds.
5. Report "Visual check needed: yes" with this Mac row. **T119 Mastery in the popover** (Mac; PDF and Markdown, light and dark): click a highlight → the popover shows "Mastery…"; it closes the popover and opens the editor sheet on the reader window; type a note, then click "Mastery…" at once → the note is kept; after saving a card, clicking the highlight again shows the "Mastery" capsule; Cancel in the editor returns to the reader with nothing changed.

## Out of scope
- "Similar" in the popover (Phase 3).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
- 2026-10-29, implementer ui-builder sonnet medium (reworks: none), reviewer code-reviewer sonnet medium: APPROVED, spec met (code-verifiable criteria); CI build and full unit tests green, 898 tests (runs 40936246463, 40936611840). Visual check pending (Mac row in VISUAL_CHECKS.md)
