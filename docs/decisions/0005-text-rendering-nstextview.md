# ADR-0005: Markdown and PDF text view render in NSTextView (TextKit 2)

- Status: Accepted
- Date: 2026-10-23

## Context
We need selectable text with exact selection ranges, range-based highlight drawing, hit testing, and paged layout, for both Markdown and reflowed PDF text.

## Decision
One shared `TextReaderView` (NSTextView, TextKit 2, read-only). Markdown is parsed with swift-markdown and rendered to `NSAttributedString` with a source map; highlights are drawn as rects from `NSTextLayoutManager` text segments in `TextReaderView.drawBackground(in:)` (amended in T63a: rendering attributes didn't paint on CI; the text storage stays untouched either way).

## Alternatives considered
Textual / MarkdownUI (SwiftUI, limited range control); WKWebView with HTML (JS bridge, offset mapping pain); SwiftUI `Text` (no selection ranges).

## Consequences
More rendering code for Markdown styling, but one highlight engine for both document kinds.
