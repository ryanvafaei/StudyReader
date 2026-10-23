# ADR-0009: PDF text view uses PDFKit text plus heuristics

- Status: Accepted
- Date: 2026-10-23

## Context
The text view needs readable reflowed text from lecture PDFs.

## Decision
Use `PDFPage.attributedString`, remove repeated headers/footers, join hyphenation and soft line breaks, keep bullets (ARCHITECTURE §6). Versioned; re-extract when the version changes.

## Alternatives considered
Vision `RecognizeDocumentsRequest` (macOS 26+) for structure: deferred as an optional improvement for poor pages; Python tools (not native).

## Consequences
Math, tables, and multi-column slides may reflow imperfectly; accepted for v1.
