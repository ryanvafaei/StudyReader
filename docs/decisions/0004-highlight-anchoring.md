# ADR-0004: Highlight anchoring model

- Status: Accepted
- Date: 2026-10-23

## Context
Highlights must redraw exactly after zoom, resize, restart, and survive text normalization changes.

## Decision
PDF view: per-line rects in PDF page space plus text/prefix/suffix. Text view and Markdown: UTF-16 offsets into the rendered string plus text/prefix/suffix and a source version; re-anchor by searching text near the old offset when the version changes; mark orphaned if not found. PDF-view and text-view highlights are separate (no mapping), like Readwise Reader.

## Alternatives considered
Mapping text-view selections back to PDF geometry; W3C selectors with XPath.

## Consequences
Simple and testable; a highlight made in one view doesn't show in the other, which the UI labels clearly.
