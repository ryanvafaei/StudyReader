# T10: Markdown fixtures and fixture loader

- **Phase:** 0
- **Agent:** data-layer
- **Depends on:** T01
- **ADRs:** docs/decisions/0011-build-signing-and-test-hosting.md (fixture folder reference)
- **Visual check needed:** no

## Goal
Commit the Markdown fixture files later tests and visual checks use (SPEC F-03 AC1 uses `all-elements.md`), a loader that finds them in the test bundle, and a helper that builds a temporary folder with a Markdown file plus a generated PNG (no binary fixtures committed). Epic E0.3.

Read first: SPEC F-03 (element list, images, front matter), F-07 AC1. ADR-0011 bullet on fixtures. `project.yml` already copies `StudyReaderTests/Fixtures/` into the test bundle as a folder reference (T01); don't change `project.yml`.

## Files to touch
- `StudyReaderTests/Fixtures/markdown/all-elements.md` (new)
- `StudyReaderTests/Fixtures/markdown/front-matter.md` (new)
- `StudyReaderTests/Fixtures/markdown/rich-inline.md` (new)
- `StudyReaderTests/Fixtures/markdown/persian.md` (new)
- `StudyReaderTests/Support/MarkdownFixtures.swift` (new)
- `StudyReaderTests/SupportTests/MarkdownFixturesTests.swift` (new)

## Fixture contents (exact; each file ends with one trailing newline)

`all-elements.md` (between the `~~~` lines):
~~~
# Heading 1

## Heading 2

### Heading 3

#### Heading 4

##### Heading 5

###### Heading 6

A paragraph with *emphasis*, **strong text**, `inline code`, ~~strikethrough~~, and a [link to Apple](https://www.apple.com).

> A block quote with **bold** inside.
> It continues on a second line.

- Unordered item one
- Unordered item two
  - Nested item

1. Ordered item one
2. Ordered item two

- [ ] Open task
- [x] Done task

| Column A | Column B | Column C |
|----------|:--------:|---------:|
| a1       | b1       | c1       |
| a2       | b2       | c2       |

```swift
let answer = 42
print(answer)
```

---

![Local diagram](images/diagram.png)

![Missing image](images/missing.png)

![Remote image](https://example.com/remote.png)

Final paragraph after the images.
~~~

`front-matter.md`:
~~~
---
title: Gradient Descent Notes
author: Ada Lovelace
course: ML1
---

# Gradient Descent

Body text after the front matter.
~~~

`rich-inline.md` (one line; this is SPEC F-07 AC1's selection text):
~~~
a **bold** and *italic* word with `code`
~~~

`persian.md` (RTL text with a zero-width non-joiner in the heading word; copy the characters exactly):
~~~
# یادداشت‌ها

این یک متن فارسی برای آزمایش برجسته‌سازی است. The word **gradient** appears in English.

- نکته اول
- نکته دوم
~~~

## Interfaces to produce

```swift
// StudyReaderTests/Support/MarkdownFixtures.swift
import Foundation

enum MarkdownFixtureError: Error { case missing(String) }

enum MarkdownFixtures {
    /// Bundle(for: BundleToken.self).url(forResource: name, withExtension: "md", subdirectory: "Fixtures/markdown")
    /// Throws .missing(name) if not found. `name` has no extension, e.g. "all-elements".
    static func url(_ name: String) throws -> URL
    static func string(_ name: String) throws -> String       // UTF-8

    /// Creates FileManager.default.temporaryDirectory/MarkdownFixtures/<UUID>/ containing:
    ///   notes.md          = contents of all-elements.md
    ///   images/diagram.png = 8×8 solid red PNG generated with CGContext + CGImageDestination (ImageIO, UTType.png)
    /// (images/missing.png is intentionally absent.) Returns the URL of notes.md.
    static func makeFolderWithImages() throws -> URL
}

private final class BundleToken {}
```

## Acceptance criteria
1. `url(_:)` finds all four fixtures and `string(_:)` returns non-empty text; an unknown name throws `.missing`. → test `MarkdownFixturesTests/fixturesLoadFromBundle`
2. Parsing `all-elements.md` with swift-markdown (`import Markdown`, `Document(parsing:)`, recursive walk over `children`) finds: `Heading` levels exactly {1,2,3,4,5,6}; `Paragraph`, `Emphasis`, `Strong`, `InlineCode`, `Strikethrough`, `Link`, `BlockQuote`, `UnorderedList`, `OrderedList`, a `ListItem` with `checkbox == .unchecked` and one with `.checked`, `Table`, `CodeBlock` with `language == "swift"`, `ThematicBreak`, and 3 `Image`s with sources `images/diagram.png`, `images/missing.png`, `https://example.com/remote.png`. → test `MarkdownFixturesTests/allElementsCoversEveryElement`
3. `front-matter.md` starts with `"---\n"`, and its first 5 lines contain `title: Gradient Descent Notes` and `author: Ada Lovelace`. → test `MarkdownFixturesTests/frontMatterFixtureShape`
4. `rich-inline.md` content, trimmed of the trailing newline, equals ``"a **bold** and *italic* word with `code`"``. → test `MarkdownFixturesTests/richInlineExact`
5. `persian.md` contains U+200C (ZWNJ) and the word `gradient`. → test `MarkdownFixturesTests/persianContainsZWNJ`
6. `makeFolderWithImages()` returns `notes.md`, with `images/diagram.png` next to it that `CGImageSourceCreateWithURL` decodes as 8×8, and no `images/missing.png`. → test `MarkdownFixturesTests/folderWithImages`

## Out of scope
- MarkdownRenderer, front-matter parsing, image copying at import (Phase 1).
- Export golden files (Phase 1). Committed binary images.

## Review log
<!-- Main session appends one line per review: date, model used, verdict, short reason -->
