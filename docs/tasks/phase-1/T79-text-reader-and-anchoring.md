# T79: Text reader and anchoring: shared normalisation, window-first scan, no fake offset 0, viewport-only highlight painting

- **Phase:** 1 (end-of-phase backlog pass, `docs/BACKLOG.md` B6 (rest), B7, B8 (comment only), B10, B18 (drawBackground); SPEC F-03, F-06)
- **Agent:** pdf-engine
- **Depends on:** none (T55, T57, T60 are done). Runs after T77 (no shared files).
- **ADRs:** ADR-0004 (anchoring), ADR-0005 (text view)
- **Visual check needed:** no
- **UI tests:** none (unit tests only)

## Goal
Make re-anchoring cheap on large Markdown documents (build the normalised text at most once per document and look near the old position first), stop the text reader from reporting position 0 when it simply can't find a line yet, and stop painting work for highlights outside the visible area.

## Files to touch
- `StudyReader/Features/Reader/Text/TextAnchoring.swift` (modify)
- `StudyReader/Features/Reader/Text/TextHighlightController.swift` (modify: `reanchorAll` only)
- `StudyReader/Features/Reader/Text/TextReaderController.swift` (modify)
- `StudyReader/Features/Reader/Text/TextReaderView.swift` (modify)
- `StudyReader/Features/Reader/Text/TextBlockDecorations.swift` (comment only)
- `StudyReaderTests/ReaderTests/TextAnchorTests.swift`, `TextReaderControllerTests.swift`, `TextHighlightControllerTests.swift` (modify)

## Interfaces to produce
```swift
extension TextAnchoring {
    /// Re-finds anchors in one text. Builds the normalised text lazily, at most once, and only when an anchor's
    /// stored range no longer holds its text.
    struct Resolver {
        init(text: String)
        mutating func resolve(_ anchor: TextAnchor, currentVersion: Int) -> Resolution
    }
}
```
`TextAnchoring.resolve(_:in:currentVersion:)` stays (same results) and becomes a one-line wrapper around a fresh `Resolver`.

## What to do
1. **B10, shared normalisation.** Add `Resolver` as above. The fast path (stored range still holds `anchor.text`) must not build `NormalizedText`. `TextHighlightController.reanchorAll` creates one `Resolver` for the rendered string and uses it for every highlight.
2. **B10, window first.** Find occurrences only inside the normalised window `[oldStart - nearbyWindow, oldStart + nearbyWindow + needle.count]` first; scan the whole text only when the window has none. Results must equal today's for every input (the window rule already restricts candidates to nearby ones when any exist). `.moved` keeps the old prefix/suffix (unchanged contract).
3. **B7.** `TextReaderController.firstVisibleOffset()` returns `Int?`: 0 for empty text, nil when text exists but no layout fragment is found. `reportPositionIfNeeded()` skips a nil offset (doesn't update `lastReportedOffset`). Adjust the restore retry at line ~98 and the two existing tests (`try #require`).
4. **B18, painting.** In `TextReaderView.drawBackground(in:)`, skip paints whose range doesn't intersect the current viewport range (`textLayoutManager?.textViewportLayoutController.viewportRange`, converted to a UTF-16 `NSRange`), and call `ensureLayout` only for the intersection. When the viewport range is nil, keep today's behaviour. Put the range logic in a pure helper: `static func paintsToDraw(_ paints: [HighlightPaint], viewport: NSRange?) -> [HighlightPaint]` (each returned paint clipped to the viewport).
5. **B6 rest.** `onClick`'s doc comment: say that the Bool result is informational (nothing runs after it in `mouseDown`); a link click never reaches it (`didClickLink`). Same note on `StudyPDFView.onClick` is NOT needed (out of this task's files).
6. **B8 comment.** On `TextBlockDecorationDelegate`'s `@preconcurrency NSTextLayoutManagerDelegate` add a one-line justification (the delegate is called on the main thread by TextKit, which isn't annotated for Swift concurrency).

## Acceptance criteria
1. `TextAnchorTests/resolverMatchesResolveForAllCases`: for every existing anchor case in the suite (unchanged, moved nearby, far move, orphaned, multiline whitespace), `Resolver(text:).resolve` == `TextAnchoring.resolve`.
2. `TextAnchorTests/fastPathDoesNotNormalise`: expose a test hook (e.g. `Resolver.hasBuiltNormalizedText`, internal) — after resolving an unchanged anchor it is false; after a moved one it is true; a second moved anchor reuses it (same instance or a build counter == 1).
3. `TextAnchorTests/windowScanFindsNearbyWithoutFullScan`: a 1 MB generated text with the needle repeated near the start and near the old position → resolves to the nearby one (existing rule), and `farMoveUsesWholeText` still passes.
4. `TextReaderControllerTests/firstVisibleOffsetIsNilWithoutLayout` (B7): a case where no fragment is found (e.g. text loaded into a view with zero width, not in a window) returns nil and reports no position; empty text returns 0. If no reliable setup exists for "no fragment", test the reporting guard instead and explain in the report.
5. `TextReaderControllerTests/paintsToDrawClipsToViewport` (B18): paints {0..<10, 50..<60, 95..<120} with viewport 40..<100 → {50..<60, 95..<100}; viewport nil → all unchanged.
6. Existing `TextAnchorTests`, `TextReaderControllerTests`, `TextHighlightControllerTests`, `ReaderModelTests` pass (`./scripts/test.sh StudyReaderTests/<each>`). `./scripts/build.sh` succeeds.

## Out of scope
The "Open Link" context-menu check (B8, Mac), recomputing prefix/suffix on `.moved`, re-anchoring on text change (not a Phase 1 flow), `ReaderModel` and the undo mark (T81), `TextHighlightController` changes other than `reanchorAll`.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
