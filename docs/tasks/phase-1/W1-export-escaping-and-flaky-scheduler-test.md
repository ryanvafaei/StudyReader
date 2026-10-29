# W1: Export escaping for titles, authors, unclosed fences and underline lines; a time-bounded wait in the scheduler tests

- **Phase:** 1 (wrap-up, user decision 2026-10-29; `docs/BACKLOG.md` B29 titles/authors, B48 line breaks, T87 spec holes (2) and (3), the red T92a master run; SPEC F-21, F-09 AC4)
- **Agent:** integrations
- **Depends on:** T95 (runs after it; last export change was T87/T94)
- **ADRs:** ADR-0007 (amendments 2026-10-28 and 2026-10-29), ADR-0018
- **Visual check needed:** no (golden files and unit tests). The real Google Docs look stays in the existing T70–T74 Mac rows.
- **UI tests:** none. Verify with `./scripts/build.sh` and the unit-test filters in acceptance criterion 9 only. No XCUITest covers the export Markdown, so no UI run is needed after this task.

## Goal
Three export changes and one test fix:
1. Document titles and authors (and the scope name in the first heading) are escaped like highlight text, with line breaks collapsed to one space. Today they go in raw, so `*`/`_` style them, a trailing `\` breaks the italic byline, and a PDF-metadata title with a line break adds body text or a second heading (BACKLOG B29, B48).
2. A note that ends inside an open backtick code fence gets a closing fence, so it can't swallow the rest of the export (T87 hole 3).
3. A note line made only of `=` or only of `-` characters is escaped, so it can't turn the line above into a setext heading or become a rule (T87 hole 2).
4. `ExportSyncSchedulerTests` waits by wall-clock time (at most 5 s) instead of counting 10,000 `Task.yield()` turns. Master run 40750816981 (T92a) failed in `ExportSyncSchedulerTests/successResetsFailureRetries()` because `waitForExports` (ExportSyncSchedulerTests.swift:70) ran out of yields on a loaded runner.

You may touch other files if needed; say so in the report, with the reason.

## Files to touch
- `StudyReader/Features/Export/ExportRenderer.swift` (modify: new `ExportMarkdownSafety.plainText(_:)`; fence and underline rules in `note(_:headings:)`; call sites in `prepare` and the H1)
- `StudyReaderTests/ExportTests/ExportRendererTests.swift` (modify: two fixtures, seven tests)
- `StudyReaderTests/Fixtures/golden/export/titles-by-document.md`, `titles-by-tag.md`, `note-blocks-by-document.md`, `note-blocks-by-tag.md` (new; the folder is already a bundle resource, as for T87: no `project.yml` change)
- `StudyReaderTests/Support/TestWait.swift` (new)
- `StudyReaderTests/CoreTests/TestWaitTests.swift` (new)
- `StudyReaderTests/ExportTests/ExportSyncSchedulerTests.swift` (modify: the wait helpers of `RecordingExporter` and `Harness.start()` only)
- `StudyReaderTests/Support/TestSleepers.swift` (modify: `ManualSleeper.waitForSleepers` only)

## Interfaces to produce
```swift
extension ExportMarkdownSafety {
    /// Plain text (a document title, an author, the scope name) made safe as inline text on one line of the export
    /// (ADR-0007 amendment 2026-10-29, W1). Line breaks collapse to one space; the text is then escaped like highlight
    /// text (`RichTextMarkdown.escape`, then `neutralise`), and a trailing `#` run after a space is escaped.
    static func plainText(_ plain: String) -> String
}

// StudyReaderTests/Support/TestWait.swift (test target only)
/// Time-bounded polling for tests (W1). Replaces "yield N times" loops, which give up too early on a loaded runner.
enum TestWait {
    static let timeout: Duration = .seconds(5)
    static let interval: Duration = .milliseconds(2)

    /// Calls `condition` until it returns true or `timeout` has passed on a `ContinuousClock`, sleeping `interval`
    /// between calls. Returns true as soon as the condition holds, false on timeout or when the task is cancelled.
    /// Callers must record an issue when it returns false, so a timeout always fails the test.
    static func until(
        timeout: Duration = TestWait.timeout,
        interval: Duration = TestWait.interval,
        _ condition: @Sendable () async -> Bool
    ) async -> Bool
}
```

## What to do

### 1. `ExportMarkdownSafety.plainText(_:)`
In this order:
1. **Line breaks:** split on every `Character` with `isNewline` (`\n`, `\r`, `\r\n`, U+2028, U+2029, U+0085, …), trim spaces and tabs from each piece, drop empty pieces, join with one space `" "`. A text without line breaks is just trimmed of spaces and tabs at both ends. (Decision: collapse to a space, never keep a second line.)
2. **Inline escape:** `RichTextMarkdown.escape(_:)` (escapes `\` `` ` `` `*` `_` `[` `]`).
3. **Block and HTML escape:** `neutralise(_:)` on the result (line-start `#` `>` `-` `+` `=` and the `.`/`)` of `1.`/`1)`; anywhere `<` `|` `~`, `&` before a letter or `#`, `!` before an unescaped `[`). This is exactly what a highlight body gets (repository `escape`, then renderer `neutralise`).
4. **Closing-sequence guard:** if the result ends with a run of `#` that is directly preceded by a space or tab, insert one `\` before that run (`Notes ##` → `Notes \##`). An ATX heading would otherwise drop it as a closing sequence. `C#` and a run preceded by `\` stay as they are.

Mid-line `#` and `>` stay raw (CommonMark treats them as text there). No special case for an empty result (titles are never empty in the database).

### 2. Where `plainText` is applied in `ExportRenderer`
- `prepare`: keep sorting on the raw `ExportDocument.title` (order unchanged), then build `Prepared` with `title: ExportMarkdownSafety.plainText(document.title)` and `author: ExportMarkdownSafety.plainText(document.author)`. Every use then gets the escaped text: `## <title>` (by document), the byline, `### <title>` (tag mode document notes) and the attribution line `_— <title>, p. N_` (tag mode). The attribution line must be escaped too: a title ending in `\` would otherwise escape the closing `_`.
- Byline: decide emptiness on the escaped author (`author.isEmpty ? categoryName : "\(author) · \(categoryName)"`), so an author made only of line breaks gives `_<category>_`.
- H1: `"# StudyReader – \(ExportMarkdownSafety.plainText(content.scopeName))"`. A document scope's name is the document title, so a title with a line break would otherwise add a second H1. Tag scope names (`#exam`) become `\#exam` there; that renders the same.
- **Not changed:** category names, tag names (`## #tag`, `- Tags:`), colour labels, the Drive file name (`StudyReader – <scope name>` in the upload metadata, `GoogleExportService`), the HTML fallback path (it converts the escaped Markdown, so escaped titles arrive as text there too).

### 3. Note rule: close an unclosed backtick fence
Add a step at the start of `note(_:headings:)`, after the `\r\n`/`\r` → `\n` normalisation and before the existing scanner:
1. Split the text on `\n` and walk the lines with CommonMark fence rules (top level only):
   - A line whose indentation (the spaces and tabs before its first other character) contains a tab or is 4+ spaces is never a fence line.
   - **Opener** (outside a block): after the indentation, a run of n ≥ 3 backticks, and the rest of the line contains no backtick. In `.bold` mode the first line is never an opener: in the export it follows `- Note: `, where a fence can't start. In `.demoted` mode every line can open.
   - **Closer** (inside a block opened with n backticks): after the indentation, a run of m ≥ n backticks followed only by spaces and tabs.
   - Lines inside a block are not checked for openers.
2. If a block is still open after the last line, append `"\n" + String(repeating: "`", count: n)` to the text.
3. Run the existing scanner unchanged on the result.

Why this is enough: the scanner copies backtick runs verbatim and only rewrites lines that start with `#`, `=` or `-` or escapes `<`, `|`, `~` outside code spans, so it never changes an opener's backticks or a closer line. The fence structure of the output is the structure of the input plus the added closer. When the scanner treats the block as one code span (opener and closer of the same length), the lines inside are copied untouched, so no heading, `#`, underline or inline rule runs inside the block.

**Tilde fences** (`~~~`) need nothing: T87's rule escapes every `~` outside code spans, so `~~~` becomes `\~\~\~` and never opens a fence in the export.

### 4. Note rule: escape a line of only `=` or only `-`
In `noteLine`, after the indentation check and before the `#` check: if the line is not a code indent (no tab, fewer than 4 spaces) and the rest of the line (from the first non-space character to the line end) is one or more `=` or one or more `-`, followed only by spaces and tabs, output the indentation, then `\`, then the rest of the line unchanged, and return the line end.

This is the minimal escape. CommonMark reads `\-` and `\=` as literal characters, and a line that starts with `\` is neither a setext underline nor a thematic break nor a list item. `neutralise` uses the same escape for highlight text (`\---`, `\===`).

Covered: `---`, `===`, `-`, `=`, `--`, any longer run, up to 3 leading spaces, trailing spaces or tabs. The rule runs on every line outside code spans and code indents, also the first line of a `.bold` note (harmless there).

**Not covered** (left as written, state it in the doc comment):
- spaced or mixed runs: `- - -`, `-- -`, `= =`, `-=`;
- thematic breaks made of `*` or `_`: `***`, `* * *`, `___`, `_ _ _`.

The spaced dash and the `*`/`_` breaks render as a horizontal rule in Google Docs, never as a heading. They are listed in BACKLOG.

### 5. What stays the same
- All T87 note rules: demoted or bold headings, the line-start `#` escape, `<` `|` `~`, code spans across lines.
- T87 hole (1), a heading or underline line inside a multi-line backtick code span, stays open (BACKLOG). So does L7 / B47: headings, fences or underlines after list or quote markers (`- # x`, a fence opened after `- ` or `> `, `> ---`).
- `neutralise`, the highlight body path, `ExportRepository`, the export layout.
- The six existing goldens are byte-identical: their titles, authors, scope names and notes contain no affected character or line.
- Keep-in-sync targets whose documents have such titles or notes re-export once after this change, because the rendered hash changes. This is expected.

### 6. Doc comments
- Extend the `ExportMarkdownSafety` type comment: three entry points; `plainText` for titles, authors and the scope name.
- Extend `note`'s comment with the fence close rule and the `=`/`-` line rule, and name the not-covered thematic-break forms.
- Extend `ExportRenderer.render`'s comment with one line: "Titles, authors and the scope name go through `ExportMarkdownSafety.plainText` (ADR-0007 amendment 2026-10-29)."

### 7. Fixtures and golden files
Add to `ExportRendererTests`:
```swift
/// The content of the title golden files (W1).
static func titlesContent() -> ExportContent {
    ExportContent(scopeName: "Titles", documents: [
        ExportDocument(
            id: "d1", title: "Alpha #1 *b* _i_ [x] <y> a|b ~s~ `c` C:\\",
            author: "Smith_J *et al.* \\", categoryName: "Paper", documentNote: "Note one.",
            highlights: [highlight("h1", color: .yellow, page: 0, body: "Body one.", tags: ["exam"], position: 1)]
        ),
        ExportDocument(
            id: "d2", title: "Beta\nSecond line\r\n# Not a heading",
            author: "Line\nBreak", categoryName: "Paper", documentNote: "Note two.",
            highlights: [highlight("h2", color: .yellow, page: 1, body: "Body two.", tags: ["exam"], position: 1)]
        ),
        ExportDocument(
            id: "d3", title: "# Overview #",
            author: "", categoryName: "Paper", documentNote: "Note three.",
            highlights: [highlight("h3", color: .yellow, page: 2, body: "Body three.", position: 1)]
        ),
    ])
}

/// The content of the note-block golden files (W1).
static func noteBlocksContent() -> ExportContent {
    ExportContent(scopeName: "Blocks", documents: [
        ExportDocument(
            id: "d1", title: "Blocks Doc", author: "", categoryName: "Paper",
            documentNote: "Summary\n---\nTotal\n===\n```swift\nlet x = 1\n# not a heading",
            highlights: [
                highlight("h1", color: .yellow, page: 0, body: "Plain body.",
                          note: "Why\n-\nBecause\n```\ncode", tags: ["exam"], position: 1),
            ]
        ),
    ])
}
```
The four golden files must have exactly this content (UTF-8, `\n` line ends, one final newline, no trailing spaces). The outer `~~~~` fences below are not part of the files.

Document order: `prepare` sorts by `localizedStandardCompare` on the raw title, which should put `# Overview #` first (symbols before letters). If your output has the same document blocks in a different order, don't change the sort. Reorder the whole document blocks in the golden and say so in the report. Any other difference: check the rules first. If you think a golden line is wrong, report it; don't edit a golden to match the output without saying so.

`titles-by-document.md` (default options):
~~~~markdown
# StudyReader – Titles

_Exported 2026-10-24 14:05 · 3 highlights from 3 documents_

## \# Overview \#

_Paper_

### Document note

Note three.

### Highlights

- **Key concept** · p. 3
  Body three.

## Alpha #1 \*b\* \_i\_ \[x\] \<y> a\|b \~s\~ \`c\` C:\\

_Smith\_J \*et al.\* \\ · Paper_

### Document note

Note one.

### Highlights

- **Key concept** · p. 1
  Body one.
  - Tags: #exam

## Beta Second line # Not a heading

_Line Break · Paper_

### Document note

Note two.

### Highlights

- **Key concept** · p. 2
  Body two.
  - Tags: #exam
~~~~

`titles-by-tag.md` (`ExportOptions(groupBy: .tag)`):
~~~~markdown
# StudyReader – Titles

_Exported 2026-10-24 14:05 · 3 highlights from 3 documents_

## #exam

- **Key concept** · p. 1
  Body one.

  _— Alpha #1 \*b\* \_i\_ \[x\] \<y> a\|b \~s\~ \`c\` C:\\, p. 1_

- **Key concept** · p. 2
  Body two.

  _— Beta Second line # Not a heading, p. 2_

## Untagged

- **Key concept** · p. 3
  Body three.

  _— \# Overview \#, p. 3_

## Document notes

### \# Overview \#

Note three.

### Alpha #1 \*b\* \_i\_ \[x\] \<y> a\|b \~s\~ \`c\` C:\\

Note one.

### Beta Second line # Not a heading

Note two.
~~~~

`note-blocks-by-document.md` (default options):
~~~~markdown
# StudyReader – Blocks

_Exported 2026-10-24 14:05 · 1 highlight from 1 document_

## Blocks Doc

_Paper_

### Document note

Summary
\---
Total
\===
```swift
let x = 1
# not a heading
```

### Highlights

- **Key concept** · p. 1
  Plain body.
  - Note: Why
    \-
    Because
    ```
    code
    ```
  - Tags: #exam
~~~~

`note-blocks-by-tag.md` (`ExportOptions(groupBy: .tag)`):
~~~~markdown
# StudyReader – Blocks

_Exported 2026-10-24 14:05 · 1 highlight from 1 document_

## #exam

- **Key concept** · p. 1
  Plain body.
  - Note: Why
    \-
    Because
    ```
    code
    ```

  _— Blocks Doc, p. 1_

## Document notes

### Blocks Doc

Summary
\---
Total
\===
```swift
let x = 1
# not a heading
```
~~~~

### 8. The time-bounded wait (test code only)
`TestWait.until` in `StudyReaderTests/Support/TestWait.swift`:
- `let clock = ContinuousClock()`, `let deadline = clock.now.advanced(by: timeout)`.
- Loop: if `await condition()` is true, return true. If `clock.now >= deadline`, return false. Otherwise `try await Task.sleep(for: interval)`; if the sleep throws (cancellation), return false.
- `Task.sleep` and the clock are fine here: this is test code. The "no `Task.sleep` in logic" rule is about app code.
- The type is an `enum` namespace on purpose: `ImportCoordinatorTests.swift` already has a file-private `pollUntil`, and `LibraryModelTests`, `NotesRepositoryTests`, `SettingsCategoryOptionsTests` and `ReaderTestSupport` have their own `waitUntil`. Don't rename or change those.

Replace these yield loops (each keeps its name and return type; each gains a trailing `sourceLocation: SourceLocation = #_sourceLocation` parameter, so call sites don't change and a failure points at the test line):
| Helper | Condition | Issue text on `false` |
|---|---|---|
| `RecordingExporter.waitForExports(_ n:)` | `await self.exported.count >= n` | `"Timed out after 5 s waiting for \(n) exports; have \(exported.count): \(exported)"` |
| `RecordingExporter.waitForHeld(_ n:)` | `await self.heldCount >= n` | `"Timed out after 5 s waiting for \(n) held exports; have \(held.count)"` |
| `RecordingExporter.waitForHashRequests(_ n:)` | `await self.hashRequests >= n` | `"Timed out after 5 s waiting for \(n) hash requests; have \(hashRequests)"` |
| `Harness.start()` (after `await scheduler.start()`) | `await scheduler.isWatchingChanges` | `"Timed out after 5 s: the scheduler never read the initial state"` |
| `ManualSleeper.waitForSleepers(_ n:)` (TestSleepers.swift) | `await self.pendingCount >= n` | `"Timed out after 5 s waiting for \(n) sleepers; have \(pendingCount)"` |

Shape (inside the actor):
```swift
func waitForExports(_ n: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
    if await TestWait.until({ await self.exported.count >= n }) { return }
    Issue.record(Comment(rawValue: "Timed out after 5 s waiting for \(n) exports; have \(exported.count): \(exported)"),
                 sourceLocation: sourceLocation)
}
```
Update `ManualSleeper.waitForSleepers`'s doc comment ("Polls up to 5 s (`TestWait`) until `n` sleeps are suspended; records an issue on timeout.").

**Nothing may be weakened:**
- No `@Test` function body in `ExportSyncSchedulerTests` changes. `git diff` of that file shows changes only inside `RecordingExporter`'s three wait helpers and `Harness.start()`. Every `#expect` after a wait stays as it is.
- A timeout always records an issue, so the test fails; it never returns silently.
- The short settle loops before negative assertions (`for _ in 0..<100` / `0..<200 { await Task.yield() }`) stay as they are. They can't fail a passing test, and turning them into sleeps would only slow the suite.
- Every test keeps `.timeLimit(.minutes(1))`. Even the longest (`successResetsFailureRetries`, about 8 waits) stays far below it in the worst case.

Users of the changed helpers (from Grep), so the reviewer can check none is weakened:
- `waitForExports`: `changeSchedulesSyncAfterDelay`, `burstOfChangesExportsOnce`, `keepInSyncOffIsIgnored`, `unchangedContentIsSkipped`, `reconnectRetriesQueued`, `queuedIsRetriedWhenOnlineAtLaunch`, `failuresRetryAFewTimesOnly`, `successResetsFailureRetries`, `queuedWhileOnlineRetriesAfterDelay`, `queuedWhileOfflineWaitsForTheNetwork`, `cancelledExportIsNotRetried`, `manualQueuedExportRetriesWhileOnline`, `manualQueuedExportWaitsForTheNetworkWhenOffline`.
- `waitForHeld`: `overlappingRequestsRunOneAfterAnother`, `queuedTargetsRetryInParallel`, `stopWhileInFlightRunsNothingAfter`.
- `waitForHashRequests`: `unchangedContentIsSkipped`.
- `Harness.start()`: every test in the suite.
- `ManualSleeper.waitForSleepers`: most `ExportSyncSchedulerTests`, and `DebouncerTests`, `NotesRepositoryTests`, `SearchModelTests`, `ReadingPositionTests`.

`TestWaitTests` (Swift Testing, `@Suite("TestWait")`):
- `returnsTrueAsSoonAsTheConditionHolds`: a condition that is already true returns true; a condition that becomes true after a few calls (count calls in a small actor) returns true.
- `returnsFalseAfterTheTimeout`: `await TestWait.until(timeout: .milliseconds(50)) { false }` is false, and at least 50 ms passed (`ContinuousClock`). Don't assert an upper bound.

## Acceptance criteria
1. `ExportRendererTests/titlesByDocument`: `render(titlesContent())` equals `titles-by-document.md`.
2. `ExportRendererTests/titlesByTag`: `render(titlesContent(), ExportOptions(groupBy: .tag))` equals `titles-by-tag.md`.
3. `ExportRendererTests/noteBlocksByDocument` and `ExportRendererTests/noteBlocksByTag`: `noteBlocksContent()` in both modes equals `note-blocks-by-document.md` / `note-blocks-by-tag.md`.
4. `ExportRendererTests/plainTextRules`, exactly these expectations:
   ```swift
   func plain(_ text: String) -> String { ExportMarkdownSafety.plainText(text) }
   #expect(plain("Lecture 3: Gradient Descent") == "Lecture 3: Gradient Descent")
   #expect(plain("Alpha #1 *b* _i_ [x] <y> a|b ~s~ `c` C:\\")
       == "Alpha #1 \\*b\\* \\_i\\_ \\[x\\] \\<y> a\\|b \\~s\\~ \\`c\\` C:\\\\")
   #expect(plain("Smith_J *et al.* \\") == "Smith\\_J \\*et al.\\* \\\\")
   // Looks like a heading, list, quote or underline
   #expect(plain("# Overview #") == "\\# Overview \\#")
   #expect(plain("## Intro") == "\\## Intro")
   #expect(plain("- Draft") == "\\- Draft")
   #expect(plain("+ Plus") == "\\+ Plus")
   #expect(plain("> Quote") == "\\> Quote")
   #expect(plain("1. Introduction") == "1\\. Introduction")
   #expect(plain("2) Methods") == "2\\) Methods")
   #expect(plain("===") == "\\===")
   // A trailing # run after a space would be read as a closing sequence
   #expect(plain("Notes ##") == "Notes \\##")
   #expect(plain("C# and F#") == "C# and F#")
   // Line breaks collapse to one space; ends trimmed
   #expect(plain("Beta\nSecond line\r\n# Not a heading") == "Beta Second line # Not a heading")
   #expect(plain("A\r\n\r\n  B \n") == "A B")
   #expect(plain("A\u{2028}B\u{85}C") == "A B C")
   #expect(plain("  Padded\t") == "Padded")
   // Other escapes from neutralise
   #expect(plain("AT&T") == "AT\\&T")
   #expect(plain("") == "")
   ```
5. `ExportRendererTests/noteFenceRules`, exactly these expectations (`note` is the same local helper as in `noteRules`):
   ```swift
   // An unclosed backtick fence is closed with a fence of the opener's length
   #expect(note("```\ncode", .demoted) == "```\ncode\n```")
   #expect(note("```swift\nlet a = 1", .demoted) == "```swift\nlet a = 1\n```")
   #expect(note("`````\nx", .demoted) == "`````\nx\n`````")
   #expect(note("  ```\ncode", .demoted) == "  ```\ncode\n```")
   // Inside the closed block nothing is rewritten
   #expect(note("```\n# Plan\n#todo a<b", .demoted) == "```\n# Plan\n#todo a<b\n```")
   // Already closed: unchanged; text after a closed block keeps the T87 rules
   #expect(note("```\ncode\n```", .demoted) == "```\ncode\n```")
   #expect(note("```\ncode\n```\n# After", .demoted) == "```\ncode\n```\n#### After")
   #expect(note("```\ncode\n````", .demoted) == "```\ncode\n````")
   // Four backticks are not closed by three
   #expect(note("````\ncode\n```", .demoted) == "````\ncode\n```\n````")
   // A closing line holds only backticks and spaces
   #expect(note("```\na ``` b", .demoted) == "```\na ``` b\n```")
   // Not fences: tildes (escaped by the T87 rule), 4-space or tab indent, two backticks, a backtick in the info string
   #expect(note("~~~\ncode", .demoted) == "\\~\\~\\~\ncode")
   #expect(note("    ```\ncode", .demoted) == "    ```\ncode")
   #expect(note("\t```\ncode", .demoted) == "\t```\ncode")
   #expect(note("``\ncode", .demoted) == "``\ncode")
   #expect(note("```a`b\ncode", .demoted) == "```a`b\ncode")
   // Highlight notes: the first line follows "- Note: ", so it never opens a fence
   #expect(note("```\ncode", .bold) == "```\ncode")
   #expect(note("Why\n```\ncode", .bold) == "Why\n```\ncode\n```")
   ```
6. `ExportRendererTests/noteUnderlineRules`, exactly these expectations:
   ```swift
   #expect(note("---", .demoted) == "\\---")
   #expect(note("===", .demoted) == "\\===")
   #expect(note("-", .demoted) == "\\-")
   #expect(note("=", .bold) == "\\=")
   #expect(note("A\n---", .demoted) == "A\n\\---")
   #expect(note("A\n===", .bold) == "A\n\\===")
   #expect(note("A\n===  ", .demoted) == "A\n\\===  ")
   #expect(note("A\n----\t", .demoted) == "A\n\\----\t")
   #expect(note("   --", .demoted) == "   \\--")
   // Not covered or not an underline: left as written
   #expect(note("    ---", .demoted) == "    ---")
   #expect(note("- item", .demoted) == "- item")
   #expect(note("-=", .demoted) == "-=")
   #expect(note("= =", .demoted) == "= =")
   #expect(note("- - -", .demoted) == "- - -")
   #expect(note("-- -", .demoted) == "-- -")
   #expect(note("***", .demoted) == "***")
   #expect(note("* * *", .demoted) == "* * *")
   #expect(note("___", .demoted) == "___")
   #expect(note("```\n---\n===\n```", .demoted) == "```\n---\n===\n```")
   ```
7. Unchanged and passing: `noteRules`, `notesByDocument`, `notesByTag`, `indentedDocumentNoteHeadingIsDemoted`, `byDocumentAllOptions`, `byTagAllOptions`, `byDocumentMinimal`, `emptyScope`, `includesNotes`, `documentsOrderedByTitle`, `noTrailingSpacesOrDoubleBlankLines`, `pageAndAuthorAreOptional`, `blockConstructsInBodyAreNeutralised`, `multiLineCodeSpanStartsNoBlock`, `safetyRules`. Reviewer: `git diff --stat StudyReaderTests/Fixtures/golden/export/` shows only the four new files.
8. `TestWaitTests/returnsTrueAsSoonAsTheConditionHolds` and `TestWaitTests/returnsFalseAfterTheTimeout` pass. Reviewer Grep: `ExportSyncSchedulerTests.swift` and `TestSleepers.swift` contain no `0..<10_000`; the `@Test` bodies of `ExportSyncSchedulerTests` are unchanged in the diff.
9. These pass: `./scripts/test.sh StudyReaderTests/ExportRendererTests StudyReaderTests/ExportRepositoryTests StudyReaderTests/GoogleExportServiceTests StudyReaderTests/ExportSyncSchedulerTests StudyReaderTests/TestWaitTests StudyReaderTests/DebouncerTests StudyReaderTests/NotesRepositoryTests StudyReaderTests/SearchModelTests StudyReaderTests/ReadingPositionTests`. `./scripts/build.sh` succeeds.

## Out of scope
- Tag names and category names in the export (raw; BACKLOG B48).
- Headings, fences or underlines after list or quote markers (BACKLOG B47 / L7), and a heading or underline inside a multi-line code span (T87 hole 1).
- Spaced, `*` or `_` thematic breaks (`- - -`, `***`, `___`).
- The HTML fallback code and the Drive file name.
- Escaping titles at import (`MetadataDefaults`).
- Any app UI, `ExportRepository`, `ExportSyncScheduler` itself.
- The settle loops in the scheduler tests, and the other suites' own `waitUntil`/`pollUntil` helpers.
- Updating BACKLOG/SPEC/ADR (done by the architect).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
