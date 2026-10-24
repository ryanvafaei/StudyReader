---
name: markdown-renderer-facts
description: How MarkdownRenderer (T43) is built and which swift-markdown / AppKit behaviours were verified
metadata:
  type: reference
---

- swift-markdown source checkout for API lookups: `build/SourcePackages/checkouts/swift-markdown/Sources/Markdown` (not `.references/`). `Document(parsing:)` default parses tables, strikethrough, task lists. Table API: `table.head.cells`, `table.body.rows`, `row.cells`; `ListItem.checkbox`, `OrderedList.startIndex`, `InlineHTML.rawHTML`.
- Renderer builds the string by recursion (not MarkupWalker): `beginBlock()` appends one "\n" copying font/paragraph/flag attributes from the previous char; empty blocks roll back. Final trim keeps U+00A0 (horizontal-rule line). Source map = inline traits only (not headings/table header).
- System-font `.bold` weight and `withSymbolicTraits(.italic)` both show up in `fontDescriptor.symbolicTraits` (verified); monospacedSystemFont reports `.monoSpace`.
- `NSImage(contentsOf:)` for an 8px PNG without DPI has size 8x8 points; NSBitmapImageRep PNG default is 72 dpi.
