# T77: PDF reader and rich-text robustness: tracking waits for a window, snapshot size cap, rotated-page tests, F-07 Markdown edge cases

- **Phase:** 1 (end-of-phase backlog pass, `docs/BACKLOG.md` B5, B9, B11 (rest), B12 (3), B14 (1)(3); SPEC F-04, F-06, F-07, F-08)
- **Agent:** pdf-engine
- **Depends on:** none (T53, T56, T58, T59, T61 are done)
- **ADRs:** ADR-0004 (anchoring)
- **Visual check needed:** no
- **UI tests:** none (unit tests only)

## Goal
Close four small robustness gaps in the PDF engine and the F-07 rich-text builder, each with unit tests: position tracking must not start before the PDF view has a window, snapshots must not allocate unbounded bitmaps, PDF anchors and `topLeftRect` must be tested on rotated and offset pages, and `RichTextMarkdown.markdown(for:in:sourceMap:)` must produce Markdown that renders as intended in the remaining edge cases.

## Files to touch
- `StudyReader/Features/Reader/PDF/PDFReaderController.swift` (modify: B5, one comment for B14 3)
- `StudyReader/Features/Reader/PDF/StudyPDFView.swift` (modify only if a window-attach hook is needed for B5)
- `StudyReader/Features/Reader/PDF/SnapshotService.swift` (modify: B14 1)
- `StudyReader/Features/Annotations/RichTextMarkdown.swift` (modify: B11)
- `StudyReaderTests/ReaderTests/PDFReaderControllerTests.swift`, `PDFAnchorTests.swift`, `SnapshotServiceTests.swift`, `PDFHighlightControllerTests.swift` (modify)
- `StudyReaderTests/AnnotationsTests/RichTextTests.swift` (modify)

## What to do
1. **B5: tracking waits for a window.** `performAfterLayout` currently runs `work` after the retry limit even when the view has no window, and `load` then calls `beginTrackingPosition()`; a later layout can report page 0 over the saved position. Change: pass `isLaidOut: Bool` to the work closure (or add a second closure). In `load`, when the limit is hit without a window, don't apply the position and don't begin tracking; remember `pendingTrackingStart = true`. When the PDF view later moves into a window (`viewDidMoveToWindow` on `StudyPDFView` calling a new `onWindowAttached` hook, or an existing hook if there is one), run the same apply-position-then-begin-tracking step once. `restore(_:)` keeps its behaviour.
2. **B14 1: snapshot size cap.** Add to `SnapshotService`: `static let maximumPixelSide = 8192`, `static let maximumPixelCount = 16_777_216` and a pure `static func pixelSize(for displayed: CGSize) -> (width: Int, height: Int)`: start at `scale` (2), reduce the effective scale so that neither side exceeds `maximumPixelSide` and `width * height <= maximumPixelCount`, round, minimum 1 per side. `renderPNG` uses it (the context scale already follows width/height).
3. **B14 3: comment.** At the `positionKey` computation in `snapshotDragFinished`, add a one-line comment: the key uses the clipped rect's top measured from the crop box's bottom (`clipped.maxY - cropBox.minY`), the same convention as `PDFAnchorBuilder` for text highlights (ARCHITECTURE §5.5). Check that `PDFAnchorBuilder` measures `firstTop` the same way; if it doesn't, report it instead of changing it.
4. **B9 and B12 3: tests only, no production change expected.** If a test exposes a real bug, fix it minimally and say so in the report.
5. **B11: rich text.** In `RichTextMarkdown.markdown(for:in:sourceMap:)`:
   - Early `break` in the entry loop once `entry.range.location >= NSMaxRange(bounds)` (entries are in ascending order; assert it in a comment, don't sort).
   - Consecutive clipped entries that touch (no gap) and share the same link destination form ONE link: `[` + their formatted bodies without the link + `](destination)`.
   - Emphasis flanking: for a run with bold and/or italic, move leading and trailing punctuation (Unicode `isPunctuation` or `isSymbol`) outside the emphasis markers, just like whitespace today (it stays inside a link's brackets). A run that is only punctuation gets no emphasis markers. Code spans are unchanged.
   - Update the doc comment.

## Acceptance criteria
1. `PDFReaderControllerTests/trackingWaitsForAWindow` (B5): a controller whose `StudyPDFView` is not in a window loads a 3-page fixture with a saved position on page 2; after the retry limit (poll up to 4 s) tracking has not started (expose `isTrackingPosition` as `private(set)` if needed) and no position was reported; then put the view in an `NSWindow` (content view, non-zero size); tracking starts (bounded wait) and the current page is page 2 (index 1).
2. `SnapshotServiceTests/pixelSizeIsCapped` (B14 1): `pixelSize(for: CGSize(width: 100, height: 50))` == (200, 100); `CGSize(width: 10_000, height: 10)` → width ≤ 8192; `CGSize(width: 5000, height: 5000)` → width·height ≤ 16_777_216 and both > 0; `CGSize(width: 0.2, height: 0.2)` → (1, 1).
3. `PDFAnchorTests/anchorsOnARotatedPageStayInsideTheCropBox` (B9): load a fixture, set `page.rotation = 90` on page 0, select a line, build the anchor with `PDFAnchorBuilder`: every rect is inside `page.bounds(for: .cropBox)` and the key orders the line before a lower line on the same page.
4. `PDFAnchorTests/anchorsWithAnOffsetCropBox` (B9): set the crop box of page 0 to `mediaBox.insetBy(dx: 36, dy: 48)` (non-zero origin); a selected line's rects lie inside the crop box; `positionKey` for two lines on the page keeps their reading order and stays within `[0, 1_000_000)` for page 0.
5. `PDFHighlightControllerTests/topLeftRectHandlesFlippedViews` (B12 3): both branches of `topLeftRect` (flipped and unflipped container) return the expected rect for one fixed input.
6. `RichTextTests/adjacentLinkRunsFormOneLink`: a link whose text is "**a** b" (bold run then plain run, same destination) → exactly one `](` in the output, e.g. `[**a** b](https://x.org)`.
7. `RichTextTests/emphasisMovesPunctuationOutside`: bold run `"x"` between `a` and `b` → `a"**x**"b`; a bold run that is only `!` → `!` without markers.
8. `RichTextTests/destinationEscaping`: destination `https://x.org/a b(c)` → `https://x.org/a%20b\(c\)`.
9. `RichTextTests/boldItalicCodePaddingAndPartialLink`: bold+italic run → `***x***`; code run starting with a backtick → padded with a longer fence; a selection covering half of a link's text → a link with that half only.
10. Existing `PDFAnchorTests`, `SnapshotServiceTests`, `PDFReaderControllerTests`, `PDFHighlightControllerTests`, `RichTextTests`, `ExportRendererTests` pass (`./scripts/test.sh StudyReaderTests/<each>`). `./scripts/build.sh` succeeds.

## Out of scope
The outline-annotation inversion check in dark mode (B14 2, Mac), click/key/undo unit tests for the PDF controller (covered by `ReaderHighlightTests`), any change to `ExportMarkdownSafety` (T80), new fixtures in `PDFFixtureBuilder` (rotate/crop in the test instead).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
