---
name: import-helpers-notes
description: T40 import helper locations (MetadataDefaults, FrontMatterParser, MarkdownImageNaming/Collector) and pitfalls (CRLF is one Character, swift-markdown walker)
metadata:
  type: reference
---

- Files: `Features/Library/Import/MetadataDefaults.swift`, `Features/Reader/Markdown/FrontMatter.swift`, `Features/Reader/Markdown/MarkdownImages.swift`; `FileStore.markdownImageURL(documentId:storedFileName:)` lives in `Core/Files/FileStore.swift`. Tests in `StudyReaderTests/LibraryTests/MetadataDefaultsTests.swift` and `StudyReaderTests/MarkdownTests/{FrontMatterTests,MarkdownImagesTests}.swift`.
- Swift `String` treats "\r\n" as ONE Character, so splitting front matter lines on `"\n"` misses CRLF. Split on `Character.isNewline` and keep index-based body slicing.
- swift-markdown: subclass-free walker is `struct X: MarkupWalker { mutating func visitImage(_:) {...}; descendInto(image) }`, then `walker.visit(Document(parsing:))`.
- Copy failures: `copyItem` errors cast to `CocoaError`; `.fileReadNoSuchFile`/`.fileNoSuchFile` = missing, anything else = unreadable. chmod 0o000 on a source reliably yields the unreadable branch in tests.
- T40 (2026-10-24): 9 tests in 3 suites, all passing.
