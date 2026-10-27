---
name: search-query-parser-notes
description: T64 SearchQueryParser tokenizer rules, file locations, and test suite
metadata:
  type: reference
---

- Files: `StudyReader/Features/Search/SearchQueryParser.swift`, tests in `StudyReaderTests/SearchTests/SearchQueryParserTests.swift` (10 tests, passing on CI run 40597350690).
- Phrase starts only when `"` opens a term (after optional `-`); a quote mid-word is ordinary text and gets doubled on output.
- A lone `-` or whitespace-only phrase is dropped. Bare `*` prefix is stripped once; empty text dropped.
