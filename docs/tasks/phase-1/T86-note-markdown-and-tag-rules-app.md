# T86: Note Markdown and tag rules in the app: one note renderer with headings, `#tag` in document notes

- **Phase:** 1 (end-of-phase backlog pass, `docs/BACKLOG.md` B29, user decision 2026-10-28; SPEC F-09 (AC3), F-10 (AC2), both updated 2026-10-28)
- **Agent:** ui-builder
- **Depends on:** T82 (`NotePreviewBlock`, the T82 block rules and `NotePreviewTests`), T85 (order only)
- **ADRs:** ADR-0007 amendment 2026-10-28 (the export side is T87; this task must use the same heading/tag rule)
- **Visual check needed:** yes, Mac only (looks of headings in rows and preview, light and dark): add one row to VISUAL_CHECKS.md "Needs a Mac". The Notes preview is also checked on CI by T88's `NotesTabTests/testPreviewRendersHeadingsListsAndTags`.
- **UI tests:** none here (unit tests only)

This task touches more files than usual (about 10), but each change is small: one new file, three view call sites, one model branch, one repository method, tests.

## Goal
The user's rule (2026-10-28): `# text` (with a space) is a heading, `#name` (no space) is always a tag, never a heading. Notes support the F-07 subset plus line breaks, lists and `#`/`##`/`###` headings (SPEC F-09).

Today the reader's Highlights tab and the browser rows show highlight notes with `Text(String)`, so raw `*` and `#` are visible, and only the Notes tab preview renders Markdown (`DocumentNotePanelView.blocks`). Also, `#tag` in a **document** note adds no tag.

After this task:
- one shared renderer draws notes in all three places, with headings bold and larger by level (the `#` marks are not shown);
- `#todo` stays plain text;
- `#tag` in a document note adds the tag to the document.

## Files to touch
- `StudyReader/Features/Annotations/NoteMarkdown.swift` (new: `NotePreviewBlock`, `NoteMarkdown`, `NoteMarkdownStyle`, `NoteMarkdownView`)
- `StudyReader/Features/Reader/Chrome/DocumentNotePanelView.swift` (modify: the preview uses `NoteMarkdownView`; the static `blocks(_:)`/`listPrefix` move out)
- `StudyReader/Features/Reader/Chrome/HighlightsPanelView.swift` (modify: the row note only)
- `StudyReader/Features/HighlightsBrowser/HighlightsBrowserView.swift` (modify: `HighlightBrowserRow` note only)
- `StudyReader/Features/Annotations/NoteEditorModel.swift` (modify: `write(_:)`, document branch)
- `StudyReader/Core/Repositories/TagRepository.swift` (modify: add one method)
- `StudyReaderTests/ReaderTests/NotePreviewTests.swift` (modify: T82's tests call `NoteMarkdown.blocks`; add the tests below)
- `StudyReaderTests/AnnotationsTests/TagParsingTests.swift`, `StudyReaderTests/AnnotationsTests/NotesRepositoryTests.swift`, `StudyReaderTests/CoreTests/TagRepositoryTests.swift` (modify)
- `VISUAL_CHECKS.md` (modify: one "Needs a Mac" row)

## Interfaces to produce
```swift
// StudyReader/Features/Annotations/NoteMarkdown.swift

/// One rendered block of a note: a paragraph, list item, heading or thematic break (T82 rules).
struct NotePreviewBlock: Equatable {          // moved here from where T82 defined it; fields from T82 plus headingLevel
    var text: AttributedString
    var indent: Int                           // list nesting depth - 1 (T82)
    var isRule: Bool                          // thematic break (T82)
    var headingLevel: Int                     // 0 = not a heading; 1...6 = ATX level (new)
}

enum NoteMarkdownStyle: Sendable {
    case regular    // Notes tab preview: body text .body
    case compact    // list rows (reader panel, browser): body text .callout
}

enum NoteMarkdown {
    /// Parses the full Markdown syntax and returns one block per paragraph, list item, heading or rule, with the
    /// T82 rules (one bullet or number per list item, indent by depth, single line breaks kept). Heading blocks have
    /// `headingLevel` set and contain only the heading text (no `#` marks). `#name` without a space is paragraph text.
    static func blocks(_ markdown: String) -> [NotePreviewBlock]

    /// Font of a heading block; nil for level 0 (use the style's body font).
    /// regular: 1 → .title2.bold(), 2 → .title3.bold(), 3...6 → .headline
    /// compact: 1 → .title3.bold(), 2 → .headline,      3...6 → .callout.bold()
    static func headingFont(level: Int, style: NoteMarkdownStyle) -> Font?
}

/// Renders note Markdown with `NoteMarkdown.blocks`. The only view that renders notes (panel rows, browser rows,
/// Notes tab preview).
struct NoteMarkdownView: View {
    init(_ markdown: String, style: NoteMarkdownStyle = .regular, maxBlocks: Int? = nil)
}

// TagRepository
/// Adds the tag to each document in one transaction. Existing links are skipped.
func addTag(_ tagId: String, toDocuments documentIds: [String]) async throws
```

## What to do
1. **Shared renderer.** Create `NoteMarkdown.swift` with the interfaces above:
   - Move T82's block parsing (`DocumentNotePanelView.blocks(_:)` and its `listPrefix` helper) and `NotePreviewBlock` there unchanged, then add `headingLevel`. Read it from the run's `presentationIntent` (`.header(level:)`).
   - Remove any heading font T82 put on the block's `AttributedString`. The view applies `headingFont(level:style:)` instead, so the style is decided in one place.
   - No copy of the parsing may stay in `DocumentNotePanelView`.
2. **`NoteMarkdownView`.**
   - Compute the blocks once in `init`. If `maxBlocks` is set, keep only the first `maxBlocks` blocks.
   - Layout: a `VStack(alignment: .leading)`, spacing 6 (regular) or 2 (compact).
   - Each block: a rule draws `Divider()`. Any other block draws `Text(block.text)` with `.font(NoteMarkdown.headingFont(level: block.headingLevel, style: style) ?? bodyFont)` (`.body` or `.callout`), `.padding(.leading, CGFloat(block.indent) * 16)` and `.frame(maxWidth: .infinity, alignment: .leading)`. In `.compact`, add `.lineLimit(2)` per block.
   - Text that fails to parse falls back to one `Text(verbatim:)` block, as T82 does.
3. **Notes tab preview** (`DocumentNotePanelView`): replace the `ForEach` over `Self.blocks(...)` with `NoteMarkdownView(noteModel.text, style: .regular)`. Keep `.textSelection(.enabled)`, the "No notes yet." empty state and `.accessibilityLabel("Note preview")` as they are.
4. **Reader panel rows** (`HighlightRowView` in `HighlightsPanelView.swift`): replace `Text(row.highlight.note).font(.callout)…lineLimit(2)` with `NoteMarkdownView(row.highlight.note, style: .compact, maxBlocks: 3).foregroundStyle(.secondary)`. The row's accessibility (combined element, label = excerpt, value = page/view) doesn't change.
5. **Browser rows** (`HighlightBrowserRow` in `HighlightsBrowserView.swift`): the same replacement for `Text(item.highlight.note)`. Keep the `trimmingCharacters` emptiness check. Touch nothing else in this file (T83 already changed the filter bar).
6. **`#tag` in document notes.** `TagRepository.addTag(_:toDocuments:)`: a mirror of `addTag(_:toHighlights:)` using `DocumentTag`, `uniqueInOrder` and the existing `documentLinkExists`. `NoteEditorModel.write(_:)`, `.document` branch: after `saveDocumentNote`, for each `TagParsing.hashTags(in: body)`, call `findOrCreate(name:at:)` and then `addTag(tag.id, toDocuments: [documentId])`. As for highlights, tags are only added: removing `#x` leaves the tag. Update the method's doc comment. **Do not change `TagParsing`** (its rules already match the user's rule: `# heading` and `##x` give nothing).
7. **VISUAL_CHECKS.md**, "Needs a Mac", one row: `| T86 | Note Markdown: a highlight note "# Why⏎*it* and **bold** #todo⏎- one" shows "Why" bold and larger, italic and bold text, "#todo" as plain text and a bullet in the reader's Highlights tab and in the Highlights browser row (at most 3 blocks, 2 lines each); the Notes tab preview shows "#", "##", "###" headings in decreasing sizes; light and dark | Seed Sample Library; type the note in the browser detail pane and the popover; type headings in the Notes tab and tick Preview |`.

## Acceptance criteria
1. `NotePreviewTests/headingLevelsAndStyling`:
   - `NoteMarkdown.blocks("# One\n\n## Two\n\n### Three\n\n#### Four\n\nplain")` gives `headingLevel` `[1, 2, 3, 4, 0]` and the texts `"One", "Two", "Three", "Four", "plain"` (`String(block.text.characters)`). No block's characters contain `"#"`.
   - `headingFont(level:style:)`: `.regular` gives 1 → `.title2.bold()`, 2 → `.title3.bold()`, 3 → `.headline`, 4 → `.headline`. `.compact` gives 1 → `.title3.bold()`, 2 → `.headline`, 3 → `.callout.bold()`. Level 0 gives nil in both styles. The three `.regular` fonts for levels 1 to 3 are pairwise different.
2. `NotePreviewTests/hashTagIsNotAHeading`:
   - `blocks("#todo review\n#exam")` gives exactly one block with `headingLevel == 0`, whose characters contain `"#todo review"` and `"#exam"`.
   - `blocks("# todo")` gives one block with `headingLevel == 1` and text `"todo"`.
3. `NotePreviewTests/inlineMarkdownInNotes`: `blocks("*it* and **bold**")` gives one block with characters `"it and bold"`. The run for "it" has `inlinePresentationIntent` containing `.emphasized`, and the run for "bold" has it containing `.stronglyEmphasized`.
4. T82's `NotePreviewTests/headingsListsRulesAndLineBreaks` and `multiParagraphListItemHasOneBullet` still pass, now calling `NoteMarkdown.blocks`. Where T82 asserted a heading font, assert `headingLevel == 1` instead.
5. `TagParsingTests/documentNoteHeadingsAndTags`: `TagParsing.hashTags(in: "# Week 1\n#exam prep, see #ML\n## Plan #ml-basics\n- item #exam")` returns `["exam", "ML", "ml-basics"]`. The existing `hashTags` test is unchanged and passes.
6. `NotesRepositoryTests/documentNoteHashTagsAddTagsToTheDocument`. Set up like `hashTagsAddTagsOnSave`, with a `.document` target.
   - Text `"# Week 1\nPlan #Exam and #ml-basics, see #exam"`, then `flush()`: `tags(forDocument:)` names are `["Exam", "ml-basics"]`, the `DocumentTag` count is 2, the `HighlightTag` count is 0, and no tag named "Week" exists.
   - Then text `"nothing"` and `flush()`: the note is `"nothing"` and the tags stay.
   - Ends with `FTSIntegrity.check`.
7. `TagRepositoryTests/addTagToDocumentsSkipsExistingLinks`: d1 already has tag A (`setTags`). `addTag(A, toDocuments: [d1, d2, d2])` leaves d1 with `[A]` and gives d2 `[A]`; the `DocumentTag` count is 2. End with `FTSIntegrity.check` like the suite's other document-writing tests.
8. Reviewer checks:
   - `DocumentNotePanelView.swift` has no `blocks(` or `listPrefix`.
   - Neither `HighlightsPanelView.swift` nor `HighlightsBrowserView.swift` contains `Text(row.highlight.note)` or `Text(item.highlight.note)`.
   - `TagParsing.swift` is unchanged (`git diff` empty).
9. `./scripts/test.sh StudyReaderTests/NotePreviewTests StudyReaderTests/TagParsingTests StudyReaderTests/NotesRepositoryTests StudyReaderTests/TagRepositoryTests StudyReaderTests/HighlightsPanelModelTests` passes; `./scripts/build.sh` succeeds.
10. VISUAL_CHECKS.md has the T86 row from step 7.

## Out of scope
The export (T87), the editors (popover, browser detail pane and Notes tab keep a plain `TextEditor` with the raw text), the highlight excerpt rendering (`RichTextView`, F-07 subset only), removing tags when `#x` is deleted from a note, any change to `TagParsing`, new XCUITests (T88), search snippets.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
