---
name: pdf-fixture-builder-notes
description: PDFFixtureBuilder (test-only generated PDFs) file locations, PDFKit font-trait API pitfalls, and what PDFKit exposes (T09)
metadata:
  type: reference
---

- `StudyReaderTests/Support/PDFFixtureBuilder.swift` (generator + presets) and `StudyReaderTests/SupportTests/PDFFixtureBuilderTests.swift` (11 tests). Presets are constants-driven; later tests should assert on `PDFFixtureBuilder.headerText`, `richRunsText`, `hyphenatedLines`, `slideBulletLines`, `coloredRect`.
- The font-trait symbol is `NSFontDescriptor.SymbolicTraits.monoSpace` (lowercase s in "Space"), not `.monospace`; compile error otherwise.
- PDFKit `page.attributedString` does expose per-run fonts for Core Text-drawn Helvetica/Menlo text: bold, italic (Oblique), and mono checks all pass via `fontName`/traits. No fallback needed.
- `CGContext(consumer:mediaBox:_:)` takes `&mediaBox` (a `var`) and `[String: Any] as CFDictionary` for the aux info; passwords go through `kCGPDFContextUserPassword`/`kCGPDFContextOwnerPassword`.
- Use `(0..<n).map { index in let page = index + 1 ... }` for page loops; `(1...max(n, 0))` crashes at n = 0.
