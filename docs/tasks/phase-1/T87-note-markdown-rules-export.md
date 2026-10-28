# T87: Note Markdown rules in the export: demoted headings, escaped line-start `#tag`, neutralised `<` `|` `~`

- **Phase:** 1 (end-of-phase backlog pass, `docs/BACKLOG.md` B29, user decision 2026-10-28; SPEC F-09 (AC4), F-21)
- **Agent:** integrations
- **Depends on:** T86 (same rule in the app; no shared files), T80 (last task that touched the export code)
- **ADRs:** ADR-0007 amendment 2026-10-28 (the rules below), ADR-0018
- **Visual check needed:** no (golden files). The real Google Docs look stays in the existing T70–T74 Mac rows.
- **UI tests:** none

## Goal
The export currently writes notes raw, so a note line `# x` becomes a top-level heading in the Google Doc and breaks its outline, and a line `#todo` could be read as a heading. The user's rule (2026-10-28) is the same in the app and the export: `# text` is a heading, `#name` is a tag.

So notes keep their inline Markdown and lists, with three changes:
- note headings are demoted below the export's own headings;
- a line-start `#` without a following space and text is escaped;
- `<`, `|` and `~` are escaped as they are for highlight text.

Titles and authors stay raw (undecided, BACKLOG B29).

## Files to touch
- `StudyReader/Features/Export/ExportRenderer.swift` (modify: `ExportMarkdownSafety.note(_:headings:)` and two call sites)
- `StudyReaderTests/ExportTests/ExportRendererTests.swift` (modify)
- `StudyReaderTests/Fixtures/golden/export/notes-by-document.md`, `notes-by-tag.md` (new)

## Interfaces to produce
```swift
extension ExportMarkdownSafety {
    /// How note headings are rewritten.
    enum NoteHeadings: Sendable {
        /// Document notes (rendered under a `###` heading): levels 1–3 become `####`; levels 4–6 stay.
        case demoted
        /// Highlight notes (inside the `- Note:` list item): any heading line becomes `**text**`.
        case bold
    }

    /// Note Markdown made safe for the export (ADR-0007 amendment 2026-10-28). Keeps inline Markdown, lists, quotes,
    /// links and code; rewrites headings; escapes a line-start `#` that isn't a heading; escapes `<`, `|`, `~`.
    static func note(_ markdown: String, headings: NoteHeadings) -> String
}
```

## What to do
1. **Rules of `note(_:headings:)`.** Normalise `"\r\n"` and `"\r"` to `"\n"`, then go line by line. Keep one character scanner (like `neutralise`) so code spans and backslash escapes are respected across lines.
   - **Lines left alone by the heading/tag rules:**
     - a line that starts inside a backtick code span opened on an earlier line (same matching as `codeSpanEnd`: a run of N backticks closes at the next run of exactly N);
     - a line whose indentation (the characters before its first non-space character) contains a tab or is 4 or more spaces (a code block or list continuation in CommonMark).
     The inline escapes (rule 4) still apply to these lines outside code spans.
   - **Heading line:** after 0 to 3 leading spaces, a run of 1 to 6 `#`, then a space or tab, then the text. The text is the rest of the line:
     - trailing spaces and tabs removed;
     - then a closing sequence removed: a trailing run of `#` that is preceded by a space or tab, or that is the whole text;
     - then trailing spaces and tabs removed again.
     If the text is not empty:
     - `.demoted`: output `"#### " + text` for levels 1 to 3, and `String(repeating: "#", count: level) + " " + text` for levels 4 to 6 (the leading spaces are dropped);
     - `.bold`: output `"**" + text + "**"`.
     The text itself gets the inline escapes (rule 4).
   - **Line-start `#` that is not a heading** (after 0 to 3 leading spaces): the `#` run isn't followed by a space or tab, or it is longer than 6, or the heading text above is empty. Insert one `\` before the first `#` and keep the rest of the line as it is (`#todo` → `\#todo`, `##x` → `\##x`, `#` → `\#`, `  #a` → `  \#a`). The rest of the line gets the inline escapes.
   - **Rule 4, inline escapes anywhere** outside code spans and existing backslash escapes: `<` → `\<`, `|` → `\|`, `~` → `\~`. Nothing else is escaped: `*`, `_`, `[`, `]`, `!`, `&`, `-`, `+`, `>`, digits and list markers stay raw, so emphasis, links, lists and quotes work in Google Docs.
   - A `#` that is not at the start of a line is never changed (`a #todo b` stays).
2. **Call sites in `ExportRenderer`:**
   - Document notes, both group-by modes (the `### Document note` block in `documentBlocks` and the `### <title>` block in `tagBlocks`): `lines(of: ExportMarkdownSafety.note(note, headings: .demoted))`.
   - Highlight notes in `itemLines`: keep the trimmed-emptiness check on the raw note, then `let noteLines = lines(of: ExportMarkdownSafety.note(note, headings: .bold))`. Leave the rest of the `- Note:` layout unchanged.
   - Highlight bodies keep `neutralise`. Titles, authors, category names and tag names are not changed.
3. **Doc comments:** add one line to `ExportRenderer.render`'s comment: "Notes go through `ExportMarkdownSafety.note` (ADR-0007 amendment)". The `ExportMarkdownSafety` type comment mentions both entry points.
4. **Goldens.** Add a fixture builder to `ExportRendererTests` and two golden files with exactly the content below (UTF-8, `\n` line ends, one final newline, no trailing spaces). The existing four goldens must not change (their notes contain no affected characters).
   ```swift
   static func notesContent() -> ExportContent {
       ExportContent(scopeName: "Notes", documents: [
           ExportDocument(
               id: "d1", title: "Notes Doc", author: "", categoryName: "Paper",
               documentNote: "# Plan\n#todo review *italic* and **bold**\n\n- first\n- second\n\n## Details\nUse <b> | x ~~y~~ and `a|b`",
               highlights: [
                   highlight("h1", color: .yellow, page: 0, body: "Plain body.",
                             note: "# Why\n#todo check **bold** and *italic*\n- one\n- two", tags: ["exam"], position: 1),
               ]
           ),
       ])
   }
   ```
   `notes-by-document.md` (default options):
   ```markdown
   # StudyReader – Notes

   _Exported 2026-10-24 14:05 · 1 highlight from 1 document_

   ## Notes Doc

   _Paper_

   ### Document note

   #### Plan
   \#todo review *italic* and **bold**

   - first
   - second

   #### Details
   Use \<b> \| x \~\~y\~\~ and `a|b`

   ### Highlights

   - **Key concept** · p. 1
     Plain body.
     - Note: **Why**
       \#todo check **bold** and *italic*
       - one
       - two
     - Tags: #exam
   ```
   `notes-by-tag.md` (`ExportOptions(groupBy: .tag)`):
   ```markdown
   # StudyReader – Notes

   _Exported 2026-10-24 14:05 · 1 highlight from 1 document_

   ## #exam

   - **Key concept** · p. 1
     Plain body.
     - Note: **Why**
       \#todo check **bold** and *italic*
       - one
       - two

     _— Notes Doc, p. 1_

   ## Document notes

   ### Notes Doc

   #### Plan
   \#todo review *italic* and **bold**

   - first
   - second

   #### Details
   Use \<b> \| x \~\~y\~\~ and `a|b`
   ```
   If your renderer output differs from these files, first check the rules above. If you believe a golden line is wrong, report it; don't edit a golden to match the output without saying so.

## Acceptance criteria
1. `ExportRendererTests/notesByDocument`: `render(notesContent())` equals `notes-by-document.md`.
2. `ExportRendererTests/notesByTag`: `render(notesContent(), ExportOptions(groupBy: .tag))` equals `notes-by-tag.md`.
3. `ExportRendererTests/noteRules`, exactly these expectations (Swift literals):
   ```swift
   func note(_ text: String, _ headings: ExportMarkdownSafety.NoteHeadings) -> String {
       ExportMarkdownSafety.note(text, headings: headings)
   }
   // Headings, demoted
   #expect(note("# A", .demoted) == "#### A")
   #expect(note("## A", .demoted) == "#### A")
   #expect(note("### A", .demoted) == "#### A")
   #expect(note("#### A", .demoted) == "#### A")
   #expect(note("##### A", .demoted) == "##### A")
   #expect(note("#\tA", .demoted) == "#### A")
   // Headings, bold; closing sequence; leading spaces
   #expect(note("# A", .bold) == "**A**")
   #expect(note("### A ###", .bold) == "**A**")
   #expect(note("   ## A", .bold) == "**A**")
   // Empty heading text, and a line-start # that isn't a heading
   #expect(note("# ##", .demoted) == "\\# ##")
   #expect(note("#todo", .bold) == "\\#todo")
   #expect(note("##x", .demoted) == "\\##x")
   #expect(note("#", .demoted) == "\\#")
   #expect(note("####### A", .demoted) == "\\####### A")
   // Untouched
   #expect(note("a #todo b", .bold) == "a #todo b")
   #expect(note("    # code", .demoted) == "    # code")
   // Inline escapes (also inside heading text), code spans, existing escapes
   #expect(note("# a<b", .demoted) == "#### a\\<b")
   #expect(note("<b> | ~~s~~", .bold) == "\\<b> \\| \\~\\~s\\~\\~")
   #expect(note("`a<b|c~d`", .bold) == "`a<b|c~d`")
   #expect(note("\\# kept \\< kept", .bold) == "\\# kept \\< kept")
   #expect(note("```\n# not a heading\n```", .demoted) == "```\n# not a heading\n```")
   // Kept as written
   #expect(note("- item\n1. one\n> quote\n*it* **b** [l](http://x.y) & !", .bold)
       == "- item\n1. one\n> quote\n*it* **b** [l](http://x.y) & !")
   // Line ends, empty input
   #expect(note("a\r\n# b", .demoted) == "a\n#### b")
   #expect(note("", .bold) == "")
   ```
4. `ExportRendererTests/includesNotes`, `byDocumentAllOptions`, `byTagAllOptions`, `byDocumentMinimal`, `emptyScope`, `noTrailingSpacesOrDoubleBlankLines`, `blockConstructsInBodyAreNeutralised` and `safetyRules` pass unchanged, and the four existing golden files are byte-identical (reviewer: `git diff --stat` on `Fixtures/golden/export/` shows only the two new files).
5. `./scripts/test.sh StudyReaderTests/ExportRendererTests StudyReaderTests/ExportRepositoryTests` passes; `./scripts/build.sh` succeeds.

## Out of scope
Escaping titles, authors, category or tag names (undecided, BACKLOG B29), changing `neutralise` or the highlight body path, the HTML fallback path, `ExportRepository`, the app's note renderer (T86), changes to the overall export layout.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
