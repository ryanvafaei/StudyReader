# T58: Rich text for Markdown highlights, and Markdown escaping

- **Phase:** 1 (E1.4: F-07 for Markdown; escaping used by PDF-view highlights)
- **Agent:** pdf-engine
- **Depends on:** T43
- **ADRs:** ARCHITECTURE §7 (SourceMap)
- **Visual check needed:** no

## Goal
Highlights store rich text as a Markdown subset: `**bold**`, `*italic*`, `` `code` ``, `[text](url)` (SPEC F-07). Build that string for a selected range of a rendered Markdown document from the renderer's source map, and provide escaping so plain text (PDF-view highlights in Phase 1) renders literally.

## Files to touch
- `StudyReader/Features/Annotations/RichTextMarkdown.swift` (new)
- `StudyReaderTests/AnnotationsTests/RichTextTests.swift` (new)

## Interfaces to produce
```swift
enum RichTextMarkdown {
    /// Backslash-escapes \ ` * _ [ ] so the text renders literally as Markdown. Newlines kept.
    static func escape(_ plain: String) -> String

    /// F-07 subset for `range` of `string`, using sourceMap entries that intersect the range (clipped to it).
    /// Plain parts are escaped. Formatting per run, nesting order: link outermost, then bold, then italic,
    /// then code innermost; code content is not escaped (use a longer backtick fence if it contains "`").
    /// Leading/trailing whitespace of a formatted run is moved outside its markers ("** bold**" never appears).
    /// Attachment characters (U+FFFC) are dropped. Other attributes (strikethrough, headings) are ignored.
    static func markdown(for range: NSRange, in string: String, sourceMap: MarkdownSourceMap) -> String
}
```

## Tests (`RichTextTests`)
- `markdownSelection` (SPEC F-07 AC1): render `MarkdownFixtures.string("rich-inline")` with `MarkdownRenderer`; select the whole string → exactly `` "a **bold** and *italic* word with `code`" ``.
- `partialSelection`: select "old and ital" (from inside "bold" to inside "italic") → `"**old** and *ital*"`.
- `linksAndNesting`: render `"See [**Apple**](https://www.apple.com) now"` and select all → `"See [**Apple**](https://www.apple.com) now"`.
- `escapesPlainText`: `escape("a*b_c [x] `y` \\")` == `"a\\*b\\_c \\[x\\] \\`y\\` \\\\"`; round trip: `AttributedString(markdown: escape(s))` characters equal `s` for a sample with all special characters.
- `codeWithBacktick`: inline code containing a backtick uses a double-backtick fence.
- `whitespaceOutsideMarkers`: (1) with rich-inline, select `" bold"` (the plain space before "bold" plus the word) → `" **bold**"`. (2) With a hand-built `MarkdownSourceMap` whose bold entry covers `" bold "` (spaces included) in the string `"a bold c"`, select all → `"a **bold** c"`.

## Acceptance criteria
1. A Markdown selection stores exactly the F-07 subset. → test `RichTextTests/markdownSelection`
2. Partial selections, links, nesting, escaping and code fences behave as specified. → tests `partialSelection`, `linksAndNesting`, `escapesPlainText`, `codeWithBacktick`, `whitespaceOutsideMarkers`

## Out of scope
- PDF attributed-selection rich text (`RichTextTests/pdfAttributedSelection`, SPEC F-07 AC2) is Phase 3 (E3.1). Rendering rich text in lists (T62, T63, T69).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
