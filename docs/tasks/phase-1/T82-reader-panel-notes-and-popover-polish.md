# T82: Reader side panel, Notes tab and popover polish: ordered refresh, live tag chips, list preview, toolbar Escape

- **Phase:** 1 (end-of-phase backlog pass, `docs/BACKLOG.md` B15 (2)–(6), B16 (1)(3)(4)(5)(6 localisation), B18 (unit test for `isReaderUndoContext`); SPEC F-06, F-09, F-10)
- **Agent:** ui-builder
- **Depends on:** T78 (`TagRepository.observeTagNamesByHighlight(inDocument:)`), T81 (runs right before; no shared files)
- **ADRs:** none
- **Visual check needed:** no for logic; the toolbar spacing and the Notes preview look go to VISUAL_CHECKS.md "Needs a Mac" (T62 and T63 rows already list them)
- **UI tests:** none (unit tests only)

## Goal
Fix the remaining reader-chrome defects from the T62/T63 reviews: the Highlights tab refreshes in order and shows tag changes at once without one query per row; the Notes tab keeps unsaved text across tab switches and its preview shows headings, nested lists, rules and line breaks; the popover stops reading image files while drawing and doesn't flush a deleted highlight's note; the selection toolbar no longer adds a phantom gap or steals Escape from the find bar.

## Files to touch
- `StudyReader/Features/Reader/Chrome/HighlightsPanelView.swift`, `HighlightsPanelModel.swift` (modify)
- `StudyReader/Features/Reader/Chrome/DocumentNotePanelView.swift` (modify)
- `StudyReader/Features/Reader/ReaderWindowView.swift` (modify: `ReaderSidePanel` only)
- `StudyReader/Features/Annotations/HighlightPopoverView.swift`, `HighlightPopoverModel.swift`, `SelectionToolbarView.swift` (modify)
- `StudyReaderTests/ReaderTests/HighlightsPanelModelTests.swift`, `StudyReaderTests/AnnotationsTests/HighlightPopoverModelTests.swift` (modify); `StudyReaderTests/ReaderTests/NotePreviewTests.swift`, `StudyReaderTests/AppTests/ReaderUndoContextTests.swift` (new)

## What to do
1. **B16 1.** `HighlightsPanelView`: replace `.task { refresh }` + `.onChange(of: model.highlights) { Task { … } }` with `.task(id: model.highlights) { await panel.refresh() }`, so a newer refresh cancels the older one.
2. **B16 3.** `HighlightsPanelModel`: drop the per-row `tags(forHighlight:)` loop. Add `func observeTagNames() async` that iterates `tagRepository.observeTagNamesByHighlight(inDocument: model.documentId)`, stores `tagNames` and rebuilds `sections` (reuse `sections(for:tagNames:fileType:)`); `refresh()` uses the stored `tagNames`. The view starts it with `.task { await panel.observeTagNames() }`. An observation error sets "Some tags couldn't be loaded."
3. **B16 6 (localisation only).** `viewLabel`: `String(localized: "PDF")` / `String(localized: "Text")`. Delete has no confirmation (spec-conform, not changed).
4. **B16 4.** `DocumentNotePanelView.blocks(_:)` returns `[NotePreviewBlock]` (`struct NotePreviewBlock: Equatable { var text: AttributedString; var indent: Int; var isRule: Bool }`): headings get a bold, larger font (`.headline`); list items get their bullet or number once per item (a second paragraph inside the same item has no new bullet) and `indent` = nesting depth − 1; a thematic break is `isRule = true` (the view draws a `Divider`); a single line break inside a paragraph is kept as a line break (F-09 "lists and line breaks"). The view indents by 16 pt per level.
5. **B16 5.** Own the document `NoteEditorModel` in `ReaderSidePanel` (`@State`, created once with `model.documentId`) and pass it into `DocumentNotePanelView(noteModel:)`, so switching Highlights ↔ Notes reuses the same model and its unsaved text. Keep the flush on disappear.
6. **B15 2.** `HighlightPopoverModel` loads the snapshot image once, off the main actor, into `private(set) var image: NSImage?` (like the panel thumbnails); `preview` uses it. No `NSImage(contentsOf:)` in `body`.
7. **B15 4.** The popover's `onDisappear` skips `note.flush()` when `model.isGone`.
8. **B15 5 and 6.** `SelectionToolbarView`: remove the hidden "Dismiss" button. Handle Escape in the existing local event monitor (add `.keyDown`): when the key is Escape (keyCode 53) and `AppCommands.isReaderUndoContext(event.window)` is true, set `model.selectionToolbar = nil` and swallow the event; otherwise pass it on (so Escape in the find bar or a text field goes there).
9. **B18 test.** Unit tests for the existing `AppCommands.isReaderUndoContext(_:)` (no production change).

## Acceptance criteria
1. `HighlightsPanelModelTests/tagChipsFollowTagChanges` (B16 3): with `observeTagNames()` running, adding a tag to a highlight of the document shows it in that row's `tagNames` without `model.highlights` changing; renaming the tag updates it (bounded waits).
2. `HighlightsPanelModelTests/viewLabelsAreLocalizedStrings`: a PDF document with both kinds gives labels equal to `String(localized: "PDF")` and `String(localized: "Text")`.
3. `NotePreviewTests/headingsListsRulesAndLineBreaks`: `"# Title\n\n- a\n  - b\n\n1. one\n2. two\n\n---\n\nline one\nline two"` → blocks: heading "Title"; "• a" indent 0; "• b" indent 1; "1. one", "2. two"; one rule; one paragraph whose characters contain "line one\nline two".
4. `NotePreviewTests/multiParagraphListItemHasOneBullet`: `"- first\n\n  second"` → exactly one block starts with "•".
5. `HighlightPopoverModelTests/goneWhenDeletedElsewhere` (B15 3): observing a highlight that another code path deletes (`highlightRepository.delete`) sets `isGone` (bounded wait).
6. `HighlightPopoverModelTests/imageLoadsOnceForSnapshot` (B15 2): an image highlight with a PNG on disk → `image != nil` after `observe()` starts (bounded wait); a text highlight → nil.
7. `ReaderUndoContextTests/readerWindowWithoutEditableResponder`: a titled `NSWindow` with an `NSView` first responder → true; with an editable `NSTextView` first responder → false; nil window → false; a window used as a sheet (`beginSheet`) → false (skip the sheet case if it can't run in the unit-test host and say so).
8. Existing `HighlightsPanelModelTests`, `HighlightPopoverModelTests`, `NoteEditorModelTests`, `ReaderModelTests` pass. `./scripts/build.sh` succeeds.
9. Reviewer check: no `NSImage(contentsOf:` in any `body`; no hidden zero-size button in `SelectionToolbarView`; `HighlightsPanelView` has no unstructured `Task` in `.onChange`.

## Out of scope
The Localizable.xcstrings refresh (B15 1, needs an Xcode build on the Mac), a delete confirmation in the panel, any change to `ReaderModel` (T81) or the Undo/Redo menu (B18 decision), new XCUITests (B17 decision).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
