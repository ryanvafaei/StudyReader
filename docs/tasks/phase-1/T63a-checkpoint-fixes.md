# T63a: T63 checkpoint fixes: seed highlight text, obsolete reader tests, highlight UI tests

- **Phase:** 1 (T63 checkpoint, `docs/checkpoints/T63-cloud-2026-10-27.md`; only spec FAILs and obsolete tests become fix tasks, everything else is in `docs/BACKLOG.md`)
- **Agent:** ui-builder
- **Depends on:** T63
- **ADRs:** docs/decisions/0019-ui-checks-xcuitest-and-peekaboo.md
- **Visual check needed:** no (covered by UI tests; the new tests are the point of this task)

## Goal
Fix what the T63 checkpoint report lists as Spec FAILs and failing tests, and add the few XCUITests that settle the open questions:
1. **Spec FAIL 1.** `SampleLibrary.swift` seeds highlights without `richText`, so the side panel and the popover show no text for them. Seed `richText` (e.g. `RichTextMarkdown.escape(text)`) and make `HighlightsPanelView` and `HighlightPopoverView` fall back to `text` when `richText` is empty.
2. **Obsolete tests.** `ReaderChromeTests/testFindAndSnapshotButtonsAreAbsent` and `testSnapshotIsDisabled` fail since T61 added the Snapshot button and enabled Document > Snapshot for a loaded PDF (SPEC F-08). Update them deliberately, per document: failed reader (both absent/disabled), PDF (Snapshot present/enabled, Find absent until T67), Markdown (Find present, Snapshot absent). State each change in the Review log; don't loosen an assertion that still holds. `testFindInDocumentIsDisabledAndListedOnce` is updated at T67, not here.
3. **Spec FAIL 2 (candidate).** Seeded Markdown highlights may not be drawn (screenshot `A9351ED0…` in the report). Add `testSeededMarkdownHighlightsAreDrawn` (report item C1): open Gradient Descent in front, wait up to 5 s for the yellow band over "lowers the loss" (pixel scan inside the reader frame), check the other three colours, count 4 panel rows. If the band is missing with the tab in front, it is a T60 bug (likely a race between `loadIfNeeded()`, `highlightsChanged()` and re-anchoring in `MarkdownReaderView.swift`, see BACKLOG B12; also check seeded anchors, OB4): find the root cause and fix it. Keep the test.
4. **Row label (BACKLOG B16-2, OB5).** The side-panel rows set `.accessibilityLabel("Highlight")`, which hides the row text from XCUITest and VoiceOver. Use the highlight text (falling back as in 1) as the label so tests can read excerpts.
5. **New tests** (report items C2, C9, C10, in new classes in `StudyReaderUITests/`): C2 the panel lists the seeded rows with their text in reading order; C9 `⌘A` then `3` creates a blue highlight (rows +1, band, selection clears) in the PDF and in the Markdown document, `3` without a selection and `⌘3`/`⌥3` change nothing (set the current colour first: highlight colour persists between launches, OB1); C10 after C9 Edit shows "Undo Highlight" and it is ENABLED for both documents and ⌘Z removes the row and band. **C10 is the T60 row flagged as a FAIL if disabled:** if the item is disabled for the Markdown view, fix it (an `undo:` responder or `validateMenuItem` override on `TextReaderView`) and say so.

## Files to touch
- `StudyReader/Core/.../SampleLibrary.swift` (find it: Debug seed), `StudyReader/Features/Reader/Chrome/HighlightsPanelView.swift`, `StudyReader/Features/Annotations/HighlightPopoverView.swift`
- `StudyReaderUITests/ReaderChromeTests.swift` and new test classes (e.g. `ReaderHighlightTests.swift`), plus helpers in `StudyReaderUITests/Support/` as needed
- Possibly `MarkdownReaderView.swift` / `TextHighlightController.swift` / `TextReaderView.swift` if 3 or 5 show a real bug

## Acceptance criteria
1. Seeded highlights show their text in the panel and the popover.
2. The two updated tests and the new tests pass on CI in one targeted run: `./scripts/ci.sh uitest StudyReaderUITests/ReaderChromeTests StudyReaderUITests/<new classes>` (this task may run its own UI tests; max 2 attempts; never two CI jobs at once). Report any failure honestly with the evidence; don't weaken a test to pass.
3. `./scripts/build.sh` and unit tests stay green (`./scripts/test.sh` by the main session).

## Out of scope
The other checkpoint items (OB2, OB3), the remaining coverage proposals C0, C3–C8, C11–C19 (BACKLOG B17), dark-mode checks.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
- 2026-10-27, implementer ui-builder Sonnet (transcript-verified) medium (rework 1: high after 18/23 UI failures), reviewer code-reviewer Sonnet high: CHANGES REQUESTED (1st): must-fix (1) canUndoHighlight stale after popover recolour/delete and panel delete (service forgets the id), (2) performUndo's direct fallback can delete a highlight behind a sheet; user decisions open: ADR-0005 amendment (highlights drawn in drawBackground instead of TextKit 2 rendering attributes) and the app-wide Undo/Redo replacement. Drawing change judged justified.
- 2026-10-27, implementer ui-builder Sonnet medium (reworks: high, high), reviewer code-reviewer Sonnet high: CHANGES REQUESTED (2nd, escalation rule: stop and ask the user). Earlier must-fix items resolved. New must-fix: (1) race when the auto-highlight mark is created: seen starts false, so if the snapshot with the new row arrives before createHighlight resumes and the row is later deleted from the panel/popover, the mark never clears (fix: seen = highlights.contains(id) at creation or reconcile right after); (2) the session-wide HighlightService remembers one lastAutoHighlightId, so across tabs ⌘Z in tab A can delete tab B's highlight (fix: undoAutoHighlight(id:) that deletes only the id the caller owns; existed since T60). Unit and UI runs green; both user decisions (ADR-0005 drawBackground painting; app-wide Undo/Redo replacement) still open.
- 2026-10-27, user decisions (AskUserQuestion): one more fix pass for the two remaining undo issues; ADR-0005 amendment (highlights drawn in drawBackground) ACCEPTED; app-wide Undo/Redo replacement ACCEPTED for now (revisit at the end-of-phase fix pass, after the user tries it on the Mac).
- 2026-10-27, implementer ui-builder Sonnet medium (reworks: high, high, high), reviewer code-reviewer Sonnet high: APPROVED (3rd review, conditional on the full unit run). Race (seen at creation) and cross-tab delete (HighlightService.undoAutoHighlight(id:)) resolved with tests; ReaderHighlightTests UI 10/10 (run 40595042303). Seeded Markdown highlights, undo, Find label, panel row value and obsolete-test fixes are in this commit; the T60 key path now registers undo (isAuto true).
