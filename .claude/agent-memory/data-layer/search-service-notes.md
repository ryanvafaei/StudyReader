# SearchService notes (T65)

Files: `StudyReader/Features/Search/SearchService.swift`, `SearchResults.swift`; wired as `AppEnvironment.searchService`.
Tests: `StudyReaderTests/SearchTests/SearchServiceTests.swift` (also holds `SearchTestEnvironment`, reusable helper) and `SearchIndexSyncTests.swift`.

- nil `SearchQueryParser.matchExpression` or `limit <= 0` returns empty results; catch `DatabaseError` with `.SQLITE_ERROR` (NUL input etc.) and return empty.
- Column filters scope hits: `{text editedText} : (expr)` for highlight text, `note : (expr)` for highlight notes. Works with the `NOT` clauses the parser emits (CI SQLite confirmed).
- Five bound-argument queries (doc text, title/author, highlight, highlight note, document note); sort each group by (rank, id), then `prefix(limit)`.
- Build `StatementArguments` from `[(any DatabaseValueConvertible)?]`, not `[any DatabaseValueConvertible]`.
- Tag filter: `highlightTag` EXISTS on `h.id` for highlight hits, `documentTag` for document hits.
- Verified on CI with filters `StudyReaderTests/SearchServiceTests StudyReaderTests/SearchIndexSyncTests` (16 tests; check the log lists them).
