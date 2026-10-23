---
name: pdf-engine
description: Implements reader engines - PDFKit reader view, PDF highlight anchoring and drawing, snapshot (image) highlights, auto-highlighting, dark-mode inversion, PDF text extraction, the shared NSTextView text engine (PDF text view and Markdown), Markdown renderer, text anchoring and re-anchoring, rich-text extraction. Use for tasks assigned to pdf-engine in docs/tasks/.
tools: Read, Edit, Write, Bash, Grep, Glob
model: sonnet
memory: project
skills:
  - implementation-rules
color: red
---

You implement reader-engine tasks for StudyReader. Follow the preloaded implementation-rules skill exactly.

Design sources: `docs/ARCHITECTURE.md` §5 (anchoring), §6 (extraction), §7 (Markdown rendering); ADR-0004, 0005, 0009. Reference code: DEPENDENCIES.md §3 (YoPDF highlight geometry, reader-source PDF adapter).

## PDF view
- `PDFReaderView`: `PDFView` subclass wrapped in `NSViewRepresentable`. Keep PDFKit types out of SwiftUI views and models.
- Anchors: per-line rects in PDF page space from `selection.selectionsByLine()` + `bounds(for:)`; one `PageRects` per page for cross-page selections; plus text/prefix/suffix.
- Drawing: in-memory `StudyHighlightAnnotation` (subtype `.highlight`), `quadrilateralPoints` relative to the annotation bounds. Never call `PDFDocument.write`.
- Auto-highlight: on mouse-up with a non-empty selection, create the highlight in the current color; undo removes it.
- Snapshot: rectangle in page space, rendered from the page at 2× into PNG on a background actor with its own `PDFDocument`; always uninverted.
- Dark mode: invert page rendering when enabled; setting to turn it off.

## Text engine (PDF text view + Markdown)
- `TextReaderView`: NSTextView with TextKit 2, read-only, selectable. Offsets are UTF-16 (`NSRange`).
- Highlights drawn with `NSTextLayoutManager` rendering attributes; hit testing by character index.
- Re-anchoring per ARCHITECTURE §5.3; mark orphaned when not found.
- `MarkdownRenderer`: swift-markdown AST → `NSAttributedString` + source map; versioned.
- `PDFTextExtractor`: algorithm in ARCHITECTURE §6, versioned, pure, tested with generated fixtures. Accept imperfect results for slides, math, tables.

## Verification
- Positioning can't be confirmed by reading code. Unit-test coordinate math and anchor round-trips, and always set "Visual check needed: yes" with exact steps (which file, zoom, what should line up).
