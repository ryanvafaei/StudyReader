# T62: Highlight popover and selection toolbar

- **Phase:** 1 (E1.4/E1.5: F-06 popover and toolbar, F-09 highlight notes, F-10 highlight tags)
- **Agent:** ui-builder
- **Depends on:** T37, T49, T59, T60
- **ADRs:** docs/decisions/0017-reader-windows-and-commands.md (requests and anchors)
- **Visual check needed:** yes

## Goal
SwiftUI UI for the two requests `ReaderModel` carries: the highlight popover (color, note, tags, Copy, Delete) when a highlight is clicked, and the floating selection toolbar (5 color dots, Note, Tag, Copy) when auto-highlight is off. Mastery… and Similar are Phase 2/3 and not shown.

## Files to touch
- `StudyReader/Features/Annotations/HighlightPopoverModel.swift` (new)
- `StudyReader/Features/Annotations/HighlightPopoverView.swift` (new)
- `StudyReader/Features/Annotations/SelectionToolbarView.swift` (new)
- `StudyReader/Features/Annotations/RichTextView.swift` (new: renders the F-07 subset)
- `StudyReader/Features/Reader/ReaderWindowView.swift` (modify: attach both to the content slot)
- `StudyReaderTests/AnnotationsTests/HighlightPopoverModelTests.swift` (new)

## Interfaces to produce
```swift
@MainActor @Observable
final class HighlightPopoverModel {
    init(highlightId: String, session: AppSession)
    private(set) var highlight: Highlight?           // live (highlightRepository.observeHighlight)
    let noteModel: NoteEditorModel                   // target .highlight(highlightId)
    let tagModel: TagFieldModel                      // target .highlight(highlightId)
    private(set) var isDeleted = false
    func observe() async                             // highlight + note load + tags
    func setColor(_ color: HighlightColor) async     // highlightService.setColor
    func delete() async                              // highlightService.delete; isDeleted = true
    /// Plain text for Copy: editedText ?? text (text highlights).
    var copyText: String { get }
    /// For image highlights: the PNG at imagePath via fileStore.url(forRelativePath:).
    var imageURL: URL? { get }
}

/// Renders a stored rich-text string (F-07 subset) with
/// AttributedString(markdown:options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)); on parse
/// failure shows the raw string.
struct RichTextView: View { init(_ markdown: String) }
```
Views:
- In `ReaderWindowView`, on the reader content: `.popover(item: $model.popoverRequest, attachmentAnchor: .rect(.rect(request.anchorRect)), arrowEdge: .bottom)` → `HighlightPopoverView(request:session:)`; and an overlay for `model.selectionToolbar` positioned just above `anchorRect` (clamped inside the view).
- Popover (width 320): five color dots (selected one ringed; tooltips = color labels from `AppSettings`; accessibility labels "Yellow, Key concept" etc.), the highlight's rich text (`RichTextView`, 4 lines max) or the image thumbnail (max height 120) for image highlights, a note editor (`TextEditor` bound to `noteModel.text`, 4–8 lines, placeholder "Add a note…", rendered preview is not needed while editing), `TagFieldView(model: tagModel)`, and buttons Copy (`NSPasteboard` plain text; image → PNG data) and Delete (destructive, no confirmation; the popover closes). `request.focus` `.note` / `.tags` puts keyboard focus in that field (`@FocusState`). On disappear: `await noteModel.flush()`.
- If `isDeleted` or the highlight disappears (deleted elsewhere), close the popover (`model.popoverRequest = nil`).
- Selection toolbar: a compact capsule with the five color dots (→ `model.applyToolbarColor`), Note (→ `applyToolbarNoteOrTag(focus: .note)`), Tag (→ `.tags`), Copy (→ `model.engineActions.copySelection?()`, toolbar closes); Escape or clicking elsewhere closes it (`model.selectionToolbar = nil`).
- All controls have accessibility labels; color dots are reachable with Tab.

## Tests (`HighlightPopoverModelTests`, `@MainActor`, in-memory environment + session)
- `colorAndDelete`: `setColor(.purple)` → stored; `delete()` → row gone, `isDeleted`.
- `copyTextPrefersEditedText`: highlight with `editedText` "Edited" → `copyText == "Edited"`; without → `text`.
- `imageURLResolves`: image highlight with a PNG written at its `imagePath` → `imageURL` exists.
- `noteAndTagsPersist` (SPEC F-06 AC5 via UI model): set `noteModel.text = "Why? #exam"`, `await noteModel.flush()`; add tag "ml" via `tagModel.add`; the highlight has the note and tags "exam", "ml".

## Acceptance criteria
1. Popover actions persist immediately. → tests `HighlightPopoverModelTests/*` (with T35's `HighlightRepositoryTests/updates`)
2. Visual check (user): click a highlight (PDF and Markdown) → popover above it with color dots (labels as tooltips), text, note field, tags, Copy, Delete; changing color recolors the highlight at once; typing a note and closing the popover keeps it after relaunch; adding a tag and `#tag` in the note both show up in the Tags section; Copy puts the text on the clipboard; Delete removes the highlight.
3. Visual check: with auto-highlight off, selecting text shows the toolbar; a color dot creates a highlight in that color; Note creates one and opens the popover with the note field focused; Tag does the same for tags; Copy copies without highlighting; Escape dismisses.
4. Visual check: image highlights show their thumbnail in the popover.

## Out of scope
- Mastery… and Similar (Phase 2/3), editing highlight text (Phase 2, F-18), the side panel (T63).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-27, implementer ui-builder Sonnet (transcript: claude-sonnet-5-5) medium (no reworks), reviewer code-reviewer Sonnet medium: APPROVED (conditional on the full unit run). Popover and selection toolbar met; note flushed on disappear; click-outside monitor removed on every path; HighlightPopoverModelTests 4/4 on CI. Nice-to-haves to BACKLOG B15.
