# T91: ⌘Z never deletes an auto-highlight that has a note, tags or edited text

- **Phase:** 1 (bug hunt `docs/bugs/phase-1.md` H1; SPEC F-06 AC1 as amended 2026-10-28)
- **Agent:** pdf-engine. Why: the auto-highlight and its ⌘Z undo are pdf-engine's domain (agent description: "auto-highlight … undo removes it"), and T81 (pdf-engine) owns `ReaderModel`'s undo mark and the controllers' registered undo action. The task also adds one method to `HighlightRepository` and changes one `HighlightService` method; both are spelled out below. `NoteEditorModel` and `TagFieldModel` are NOT changed.
- **Escalation (CLAUDE.md):** Sonnet agent. 1st rejection → same agent, effort `high`, with the spec and the review report. 2nd rejection → stop and ask the user. Reviews after an escalation run code-reviewer with effort `high`.
- **Depends on:** T90 (last committed task); context T81 (undo mark), T63a (app-wide Undo)
- **ADRs:** ADR-0017 (reader windows and commands), ADR-0012 (data-layer conventions)
- **Visual check needed:** yes (Mac row "T91" in VISUAL_CHECKS.md "Needs a Mac", added by the orchestrator from the report)
- **UI tests:** none. Verify with `./scripts/build.sh` and unit-test filters only.

## Goal
Today, after an auto-highlight is created, typing a note in its popover or adding a tag doesn't end the ⌘Z window: the note goes through `NoteEditorModel` → `HighlightRepository.updateNote`, tags through `TagFieldModel` → `TagRepository`, neither tells `HighlightService` (which forgets `lastAutoHighlightId` only for its own calls), and `ReaderModel.reconcileAutoHighlightMark` drops the mark only on delete or recolour. So Edit > Undo still reads "Undo Highlight" and ⌘Z deletes the highlight with its note and tags, with no redo.

**Chosen behaviour (simplest rule that can't destroy user text):** Undo removes an auto-highlight only while it is still bare. Two layers:
1. **Hard guard at the delete.** `HighlightService.undoAutoHighlight(id:)` deletes through a new repository method that, in one write transaction, deletes the row only if it has no note text, no edited text and no tag links. Every path that annotates (popover, browser detail pane, Notes typing `#tag`, browser bulk Add Tag, tag field) is covered, because the check reads the database at the moment of the delete.
2. **Menu state.** `ReaderModel` drops its undo mark as soon as the live row shows a note or edited text, and when the user opens the popover on that highlight. So in the normal case Edit > Undo stops reading "Undo Highlight" before the user can press ⌘Z. A tag-only change made outside the popover (browser bulk Add Tag in the library window) isn't visible in `Highlight` rows; there the menu may still read "Undo Highlight" once, and ⌘Z then removes nothing and ends the undo window (guard 1).

Opening the popover counts as annotating because the popover is where notes and tags are typed. It also closes the gap where a note is still inside the 500 ms autosave delay when the popover closes and the user presses ⌘Z at once.

## Files to touch
- `StudyReader/Core/Repositories/HighlightRepository.swift` (modify: add `deleteIfUnannotated`)
- `StudyReader/Features/Annotations/HighlightService.swift` (modify: `undoAutoHighlight(id:)` uses it; doc comments)
- `StudyReader/Features/Reader/ReaderModel.swift` (modify: `reconcileAutoHighlightMark`, `showPopover`, the `autoHighlightMark` doc comment)
- `StudyReaderTests/CoreTests/HighlightRepositoryTests.swift`, `StudyReaderTests/AnnotationsTests/HighlightServiceTests.swift`, `StudyReaderTests/ReaderTests/ReaderModelTests.swift` (modify: new tests)
- You may touch other files if the diagnosis requires it; list each one and the reason in the report.

## Interfaces to produce
```swift
extension HighlightRepository {
    /// Deletes the row only when it is still bare: `note` is nil or empty after trimming whitespace and newlines,
    /// `editedText` is nil, and no `highlightTag` row references it. The check and the delete run in ONE write
    /// transaction (a note or tag written just before can't slip between them). On delete, removes the snapshot
    /// file like `delete(id:fileStore:)`. Returns true when the row was deleted; false when it is missing or annotated
    /// (nothing changed).
    @discardableResult
    func deleteIfUnannotated(id: String, fileStore: FileStore) async throws -> Bool
}
```
`HighlightService.undoAutoHighlight(id:) async throws -> String?` keeps its signature. New contract: returns `id` only when the remembered auto-highlight was deleted; returns nil when `id` is not the remembered one OR the row is annotated or missing (`deleteIfUnannotated` returned false). In every case where `lastAutoHighlightId == id`, the service forgets it (as today, before the delete). Errors from the write still throw.

## What to do
1. **Repository.** Implement `deleteIfUnannotated` as above in a single `writer.write` closure: fetch the row, check the three conditions in Swift (trim with `.whitespacesAndNewlines`, the SQL `TRIM` only strips spaces, see BACKLOG B45, bug hunt L5), count `highlightTag` rows for the id, delete only if all three hold. Column-limited rules (ADR-0012) don't apply to a delete; no `update(db)`.
2. **Service.** `undoAutoHighlight(id:)`: `guard lastAutoHighlightId == id else { return nil }`, `lastAutoHighlightId = nil`, then `try await highlights.deleteIfUnannotated(id: id, fileStore: fileStore) ? id : nil`. Update the doc comment ("…and only while it has no note, tags or edited text"). `delete(id:)`/`delete(ids:)` are unchanged (explicit deletes still delete annotated highlights).
3. **ReaderModel mark.**
   - `reconcileAutoHighlightMark()`: besides "gone" and "other colour", also drop the mark when the live row has `note` non-empty after trimming whitespace and newlines, or `editedText != nil`.
   - `showPopover(highlightId:anchorRect:focus:)`: when `highlightId == autoHighlightMark?.id`, set `autoHighlightMark = nil` before setting `popoverRequest`. A popover for another highlight leaves the mark alone.
   - `undoLastAutoHighlight()`: unchanged code; after a nil result from the service the mark is cleared as today. Update the `autoHighlightMark` doc comment to list the new reasons.
   - Don't change `AppCommands.performUndo`, the controllers' registered undo actions, `NoteEditorModel` or `TagFieldModel`.

## Acceptance criteria
1. `HighlightRepositoryTests/deleteIfUnannotatedKeepsAnnotatedRows`: rows with note `"x"`, with `editedText` `"e"`, and with one tag link are kept (`false`, row and link still there); a row with note `" \n\t"` and a bare row are deleted (`true`); an unknown id returns `false`. Ends with `FTSIntegrity.check` (the table is FTS-indexed, ARCHITECTURE §15).
2. `HighlightServiceTests/undoKeepsAnAnnotatedAutoHighlight`: `createText(_, isAuto: true)`, then `HighlightRepository.updateNote(id:note:"exam: derive this"…)`; `undoAutoHighlight(id:)` returns nil, the row exists with its note; a second call also returns nil (forgotten). Same test (second part) with a tag added through `TagRepository.addTag(_:toHighlights:)` instead of a note: nil, row and link kept.
3. `HighlightServiceTests/autoHighlightUndo`, `undoOnlyRightAfter`, `undoOnlyDeletesTheCallersOwnAutoHighlight` pass unchanged (a bare auto-highlight is still removed).
4. `ReaderModelTests/undoIsClearedWhenANoteIsSaved` (the bug hunt's failing test): `modelWithAutoHighlight`, then a `NoteEditorModel(target: .highlight(id), environment:)` is loaded, its `text` set to `"exam: derive this"` and flushed; `waitUntil { !model.canUndoHighlight }` is true; `await model.undoLastAutoHighlight()` leaves the highlight count at 1 with the note intact.
5. `ReaderModelTests/undoAfterATagOnlyLeavesTheHighlight`: `modelWithAutoHighlight`, then `TagRepository.findOrCreate` + `addTag(_:toHighlights:)` for it; `await model.undoLastAutoHighlight()` → highlight count 1, tag link kept, `canUndoHighlight == false` afterwards.
6. `ReaderModelTests/openingThePopoverEndsTheUndoWindow`: `modelWithAutoHighlight`; `showPopover(highlightId: <other id>, anchorRect: .zero)` keeps `canUndoHighlight` true; `showPopover(highlightId: highlight.id, anchorRect: .zero)` makes it false and sets `popoverRequest`.
7. Existing `ReaderModelTests` undo tests (`undoIsClearedWhenThePopoverRecolorsTheAutoHighlight`, `undoIsKeptWhenThePopoverPicksTheCurrentColor`, `undoIsClearedWhenThePopoverDeletesTheAutoHighlight`, `undoIsClearedWhenThePanelDeletesTheAutoHighlight`, `undoIsClearedByAPanelDeleteWhenTheSnapshotLandedBeforeTheMarkWasSet`, `undoInOneTabKeepsAnotherTabsAutoHighlight`, `undoIsClearedWhenAnotherHighlightFailsToSave`, `failedUndoKeepsTheMark`) and `TextHighlightControllerTests/autoHighlightCreatesCollapsesAndUndoes`, `PDFHighlightControllerTests` pass unchanged.
8. `./scripts/test.sh StudyReaderTests/HighlightRepositoryTests StudyReaderTests/HighlightServiceTests StudyReaderTests/ReaderModelTests StudyReaderTests/TextHighlightControllerTests StudyReaderTests/PDFHighlightControllerTests` passes; `./scripts/build.sh` succeeds.
9. Reviewer check on the diff: the annotation check and the delete are in one `writer.write`; no `NoteEditorModel`, `TagFieldModel` or `AppCommands` change; `undoAutoHighlight` still forgets the id before deleting.
10. Visual check (Mac, VISUAL_CHECKS row "T91"): auto-highlight on; select a sentence (PDF and Markdown) → Edit > Undo reads "Undo Highlight"; click the highlight, type a note, add a tag, close the popover → Edit > Undo no longer reads "Undo Highlight" and ⌘Z keeps the highlight, its note and tag; a fresh bare auto-highlight is still removed by ⌘Z.

## Out of scope
- The B18 Undo/Redo replacement, Redo behaviour, the T81 follow-up "failed undo already cleared the id" (BACKLOG), L1 (note saves re-add tags), L2 (lost updates).
- Watching tag links in `ReaderModel` (a tag-only change from the library window is covered by the guard, not by the menu title).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
2026-10-28, implementer pdf-engine Sonnet high (no reworks), reviewer code-reviewer Sonnet medium: APPROVED, CI green (run 40747845323, 702 tests); no spec deviations; undo on an annotated auto-highlight is a silent no-op that keeps the highlight; tag added through the browser bulk bar while the mark is live is the accepted edge case (VISUAL_CHECKS T91)
