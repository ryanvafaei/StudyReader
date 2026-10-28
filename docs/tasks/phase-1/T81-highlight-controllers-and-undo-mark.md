# T81: Highlight controllers and the auto-highlight undo mark: shared key mapping, result-based collapse, stale pending highlight, safe undo

- **Phase:** 1 (end-of-phase backlog pass, `docs/BACKLOG.md` B13 (1)(2)(3), B19 (1); SPEC F-06)
- **Agent:** pdf-engine
- **Depends on:** T79 (shares `TextHighlightController.swift`; T80 runs in between), T77 (shares `PDFReaderController.swift`, `PDFHighlightControllerTests.swift`)
- **ADRs:** ADR-0004
- **Visual check needed:** no
- **UI tests:** none (unit tests only; `ReaderHighlightTests` cover key 3 and Undo at the next UI run)

## Goal
Remove four small correctness risks around highlight creation: the 1–5/H key mapping lives in a neutral helper, collapsing the selection and registering ⌘Z depend on the created highlight rather than on the banner text, a `.highlight(id)` location for a deleted highlight no longer stays pending forever, and a failed undo keeps its mark.

## Files to touch
- `StudyReader/Features/Annotations/HighlightKeys.swift` (new)
- `StudyReader/Features/Reader/PDF/PDFHighlightController.swift` (modify)
- `StudyReader/Features/Reader/Text/TextHighlightController.swift` (modify)
- `StudyReader/Features/Reader/ReaderModel.swift` (modify)
- `StudyReader/Features/Reader/PDF/PDFReaderController.swift` (modify: `applyPendingLocation` only)
- `StudyReader/Features/Reader/Markdown/MarkdownReaderView.swift` (modify: `MarkdownReaderCoordinator.applyPendingLocation` only)
- `StudyReaderTests/ReaderTests/PDFHighlightControllerTests.swift`, `ReaderModelTests.swift`, `TextHighlightControllerTests.swift`, `PDFReaderControllerTests.swift` (modify); `StudyReaderTests/AnnotationsTests/HighlightKeysTests.swift` (new)

## Interfaces to produce
```swift
/// Keys 1–5 pick the palette colours, H (either case) the current colour; anything else nil (SPEC F-06).
enum HighlightKeys {
    static func color(forKey key: String?, current: HighlightColor) -> HighlightColor?
}

// ReaderModel
/// true after the first emission of observeHighlights().
private(set) var hasLoadedHighlights: Bool
/// Returns the created highlight (auto-highlight on), nil when the toolbar is shown or creation failed.
@discardableResult
func selectionFinished(_ new: NewTextHighlight, anchorRect: CGRect) async -> Highlight?
```

## What to do
1. **B13 1.** Move `PDFHighlightController.color(forKey:current:)` unchanged into `HighlightKeys.color(forKey:current:)`; both controllers call it; delete the old static. Move its test into `HighlightKeysTests/keysMapToColors`.
2. **B13 2.** `ReaderModel.selectionFinished` returns the highlight from `createHighlight` (nil in the toolbar branch). In both controllers' `selectionFinished`, collapse the selection and register the undo action only when the returned highlight is non-nil (drop the `model.transientMessage == nil` check). The key paths already check the result; leave them.
3. **B13 3.** Set `hasLoadedHighlights = true` on the first emission in `observeHighlights()`. In `PDFReaderController.applyPendingLocation` and `MarkdownReaderCoordinator.applyPendingLocation`, when the location is `.highlight(id)`, `reveal` returns false and `model.hasLoadedHighlights` is true, consume the location (the highlight is gone) instead of keeping it pending.
4. **B19 1.** `ReaderModel.undoLastAutoHighlight()`: keep the mark until `undoAutoHighlight(id:)` succeeds; clear it then. On a thrown error keep the mark and set `transientMessage` as today.

## Acceptance criteria
1. `HighlightKeysTests/keysMapToColors`: the nine expectations of the old PDF test (1, 3, 5, h, H, 6, 0, x, nil) hold for `HighlightKeys`.
2. `ReaderModelTests/selectionFinishedReturnsTheHighlight`: auto-highlight on → non-nil with the current colour; off → nil and `selectionToolbar != nil`.
3. `ReaderModelTests/selectionFinishedReturnsNilOnFailure`: a highlight service that throws (e.g. a document id that doesn't exist, or the existing failure setup in the suite) → nil, `transientMessage != nil`, `canUndoHighlight == false`.
4. `ReaderModelTests/hasLoadedHighlightsAfterFirstEmission`: false before `observeHighlights()` emits, true after (bounded wait), also for a document with no highlights.
5. `PDFReaderControllerTests/deletedHighlightLocationIsConsumed`: after load and tracking, navigate to `.highlight("missing-id")` with highlights loaded → `model.pendingLocation == nil` after `applyPendingLocation()`; before the first emission (fresh model) it stays pending.
6. `TextHighlightControllerTests/deletedHighlightLocationIsConsumed` (or the coordinator's test file if that is where `MarkdownReaderCoordinator` is tested): same rule for the Markdown reader.
7. `ReaderModelTests/failedUndoKeepsTheMark`: create an auto-highlight, make the delete fail (e.g. delete the row's document so `undoAutoHighlight` throws, or use a failing service stub if the suite has one; if the service can't be made to throw without a seam, say so and test the success path ordering instead) → `canUndoHighlight` stays true and `transientMessage` is set.
8. Existing `ReaderModelTests`, `PDFHighlightControllerTests`, `TextHighlightControllerTests`, `PDFReaderControllerTests`, `HighlightServiceTests` pass. `./scripts/build.sh` succeeds.

## Out of scope
A stale mark after another tab or a same-colour bulk recolour (B19 2, accepted: it clears after one ⌘Z), the app-wide Undo/Redo replacement (B18, user decision after the Mac trial), re-anchoring on text change, `TextAnchoring` (T79).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
2026-10-28, implementer pdf-engine Sonnet high (no reworks), reviewer code-reviewer Sonnet medium: APPROVED, CI green (run 40686384468, 668 tests); no spec deviations; minor follow-up (failed undo then retry clears the mark without deleting) in BACKLOG
