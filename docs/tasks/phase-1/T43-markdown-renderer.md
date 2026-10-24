# T43: MarkdownRenderer (swift-markdown → NSAttributedString + source map)

- **Phase:** 1 (E1.3: F-03 rendering engine; source map for F-07)
- **Agent:** pdf-engine
- **Depends on:** T40
- **ADRs:** docs/decisions/0005-text-rendering-nstextview.md, docs/decisions/0016-import-pipeline-and-stored-files.md (Markdown images), ARCHITECTURE §6 (last paragraph), §7
- **Visual check needed:** no (T55 shows it on screen)

## Goal
Render a stored Markdown file into an `NSAttributedString` with distinct styling for every F-03 element, a source map of inline formatting (for rich-text highlights, T58), and section ranges for search units (T44). The rendered string is the coordinate space of Markdown text anchors, so output must be deterministic and versioned.

## Files to touch
- `StudyReader/Features/Reader/Markdown/MarkdownRenderer.swift` (new)
- `StudyReader/Features/Reader/Markdown/MarkdownStyle.swift` (new: fonts, paragraph styles, custom attribute keys)
- `StudyReader/Features/Reader/Markdown/MarkdownSourceMap.swift` (new)
- `StudyReaderTests/MarkdownTests/MarkdownRendererTests.swift` (new)

## Interfaces to produce
```swift
struct MarkdownRenderStyle: Sendable, Equatable {
    var baseFontSize: CGFloat = 16          // F-05 default; appearance settings arrive in Phase 3
    static let standard = MarkdownRenderStyle()
}

struct MarkdownDocumentSource: Sendable {
    var markdown: String                    // full file text, front matter included
    var documentId: String?                 // for image lookup via FileStore; nil = no local images
    var fileStore: FileStore?
}

struct InlineTraits: OptionSet, Sendable, Hashable {
    let rawValue: Int
    static let bold = InlineTraits(rawValue: 1)
    static let italic = InlineTraits(rawValue: 2)
    static let code = InlineTraits(rawValue: 4)      // inline code and code blocks
    static let link = InlineTraits(rawValue: 8)
}
struct MarkdownSourceMap: Sendable, Equatable {
    struct Entry: Sendable, Equatable {
        var range: NSRange          // UTF-16 range in the rendered string
        var traits: InlineTraits
        var linkDestination: String?
    }
    /// Sorted by range.location, non-overlapping, covering every rendered character that has traits.
    var entries: [Entry]
}

/// Not Sendable (NSAttributedString); build and use it in one isolation domain.
struct RenderedMarkdown {
    let attributedString: NSAttributedString
    let sourceMap: MarkdownSourceMap
    /// Search units (ARCHITECTURE §6): a new section starts at each H1 or H2 heading; text before the first one is
    /// section 0 (omitted when empty). Sections partition the string exactly (no gaps, no overlap).
    let sections: [NSRange]
    let frontMatter: FrontMatter
    var string: String { attributedString.string }
}

enum MarkdownRenderer {
    /// Bump when the rendered string can change (triggers re-anchoring, ARCHITECTURE §5.3).
    static let version = 1
    /// Pure and deterministic. Callable off the main actor: only Foundation/AppKit value types
    /// (NSFont, NSColor, NSParagraphStyle, NSImage, NSTextAttachment); no views.
    static func render(_ source: MarkdownDocumentSource, style: MarkdownRenderStyle = .standard) -> RenderedMarkdown
}

extension NSAttributedString.Key {
    static let studyCodeBlock: NSAttributedString.Key      // Bool; the text view draws a background (T55)
    static let studyBlockQuote: NSAttributedString.Key     // Bool; the text view draws a left bar (T55)
    static let studyHorizontalRule: NSAttributedString.Key // Bool
}
```

## Rendering rules
- Strip front matter with `FrontMatterParser.split` (T40) before parsing; return it in `frontMatter`. The rendered string never contains front matter.
- Parse with `Document(parsing: body)` (default options: CommonMark + GFM tables, strikethrough, task lists).
- Block separation: blocks are separated by exactly one `"\n"` character (paragraph spacing comes from `NSParagraphStyle.paragraphSpacing`, not from extra newlines). The string never starts or ends with whitespace.
- Headings H1–H6: system font sizes 2.0, 1.6, 1.35, 1.2, 1.05, 1.0 × base, semibold/bold.
- Paragraphs: base size, line height multiple 1.4.
- Emphasis → italic trait, strong → bold trait, strikethrough → `.strikethroughStyle`, inline code → monospaced (`NSFont.monospacedSystemFont`) + `.code` in the source map.
- Code blocks: monospaced 0.9 × base, `.studyCodeBlock = true`, no syntax colours; the fenced language is not shown.
- Block quotes: `.studyBlockQuote = true`, head indent 16 pt, secondary label colour.
- Lists: markers are part of the string: unordered `"•\t"`, nested `"◦\t"`, ordered `"1.\t"`, task `"☐\t"` / `"☑\t"`; tab stops and head indents per nesting level (20 pt per level).
- Tables: one line per row, cells separated by `"\t"`, tab stops evenly spaced; header row bold.
- Links: `.link` attribute (URL) and `.link` trait with `linkDestination`.
- Horizontal rule: a line with one U+00A0 character carrying `.studyHorizontalRule = true` (the text view draws the rule).
- Images: one U+FFFC attachment character. Local: if `MarkdownImageNaming.storedFileName(forSource:)` is non-nil and `fileStore.markdownImageURL(documentId:storedFileName:)` exists, an `NSTextAttachment` with that image (scaled to at most 720 pt wide). Otherwise a placeholder attachment image (rounded box, alt text, or the URL for remote sources) generated with `NSImage(size:flipped:drawingHandler:)`.
- Source map: every run with bold/italic/code/link traits gets an entry; merge adjacent runs with equal traits and destination.

## Tests (`MarkdownRendererTests`)
- `rendersAllElements`: `MarkdownFixtures.string("all-elements")` → string contains "Heading 1", "Heading 6", "emphasis", "strong text", "inline code", "Unordered item one", "Ordered item one", "Column A\tColumn B\tColumn C", "let answer = 42", "Final paragraph after the images."; does not contain "```", "**", "|", "- [ ]". Attributes: the H1 font is larger than the paragraph font; "strong text" has a bold font; "emphasis" italic; "inline code" monospaced; "let answer" has `.studyCodeBlock`; the block quote text has `.studyBlockQuote`; "link to Apple" has `.link` == `https://www.apple.com`; "strikethrough" has `.strikethroughStyle`.
- `imagesAndPlaceholders`: with `makeFolderWithImages()` imported by copying `diagram.png` to `markdownImageURL` for a temp `FileStore` + id: the string has 3 U+FFFC characters; the first attachment's image is 8 × 8 px red source scaled; the second and third are placeholders (attachment image non-nil, different from the first).
- `hidesFrontMatter`: `front-matter.md` → string starts with "Gradient Descent" and doesn't contain "title:" or "---"; `frontMatter.title == "Gradient Descent Notes"`.
- `sourceMapForRichInline`: `rich-inline.md` → string == `"a bold and italic word with code"`; entries: bold over "bold", italic over "italic", code over "code" (exact NSRanges).
- `sectionsPartitionString`: a document `"Intro\n\n# A\n\ntext\n\n## B\n\nmore\n\n### C\n\nx"` → 3 sections (intro, A…, B… including C); concatenating the section substrings equals the string.
- `deterministic`: rendering the same source twice gives equal strings, equal source maps and equal sections.
- `rendersOffMainActor`: `await Task.detached { MarkdownRenderer.render(...) }.value.string` is non-empty (compile and run check for the off-main requirement; return only the string).

## Acceptance criteria
1. Every F-03 element renders with distinct styling attributes. → test `MarkdownRendererTests/rendersAllElements` (the on-screen check is T55)
2. Local images render, missing and remote ones show placeholders, and remote ones are never fetched. → test `MarkdownRendererTests/imagesAndPlaceholders` + code review (no URLSession/Data(contentsOf: remote))
3. Front matter is hidden. → test `MarkdownRendererTests/hidesFrontMatter` (SPEC F-03 AC3, rendering half)
4. The source map and sections are exact and deterministic. → tests `sourceMapForRichInline`, `sectionsPartitionString`, `deterministic`, `rendersOffMainActor`

## Out of scope
- The text view, drawing of custom attributes, link clicks (T55). Rich-text Markdown output (T58). Appearance settings (Phase 3).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
