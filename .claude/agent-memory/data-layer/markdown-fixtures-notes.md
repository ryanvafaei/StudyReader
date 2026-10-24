---
name: markdown-fixtures-notes
description: Markdown fixture files, MarkdownFixtures loader and makeFolderWithImages helper locations and pitfalls (T10, T28)
metadata:
  type: reference
---

- Markdown fixtures live in `StudyReaderTests/Fixtures/markdown/` (`all-elements`, `front-matter`, `rich-inline`). The `persian` fixture was removed in T28 (English-only scope). Loader: `StudyReaderTests/Support/MarkdownFixtures.swift` (`url`, `string`, `makeFolderWithImages`). Tests: `StudyReaderTests/SupportTests/MarkdownFixturesTests.swift` (5 tests).
- `MarkdownFixtureError` has only `.missing(String)` and is not Equatable, so `#expect(throws: MarkdownFixtureError.missing(...))` fails to compile. Use a do/catch with `catch MarkdownFixtureError.missing(let name)` instead.
- `makeFolderWithImages()` copies `all-elements.md` to `notes.md` and writes an 8×8 red PNG via CGContext + CGImageDestination (`UTType.png.identifier as CFString`). Its folder is under `temporaryDirectory/MarkdownFixtures/<UUID>/`; tests remove it with `defer`.
- swift-markdown walk: `Document(parsing:)` plus a recursive `children` flatten. `ListItem.checkbox` is `Checkbox?`, `Image.source` is `String?`.
