# T76: Search hardening: NUL and punctuation-only terms, narrow FTS error handling, merge order

- **Phase:** 1 (end-of-phase backlog pass, `docs/BACKLOG.md` B20, B21, B22 (3); SPEC F-12)
- **Agent:** data-layer
- **Depends on:** none (T64, T65, T66 are done)
- **ADRs:** ADR-0014 (tokenizer)
- **Visual check needed:** no
- **UI tests:** none (unit tests only)

## Goal
Make the search parser and service robust against odd input without hiding real database errors: drop NUL scalars and terms that can never match, stop treating every `SQLITE_ERROR` as "rejected by FTS5", give merged document hits a numeric tie-break, and cover the error path in `SearchModel`.

## Files to touch
- `StudyReader/Features/Search/SearchQueryParser.swift` (modify)
- `StudyReader/Features/Search/SearchService.swift` (modify)
- `StudyReaderTests/SearchTests/SearchQueryParserTests.swift` (modify)
- `StudyReaderTests/SearchTests/SearchServiceTests.swift` (modify)
- `StudyReaderTests/SearchTests/SearchModelTests.swift` (modify)

## What to do
1. **NUL (B20 1).** In `SearchQueryParser.terms(in:)` skip every U+0000 scalar (treat it as if it weren't there, not as whitespace). Update the doc comment.
2. **Terms that can't match (B20 2).** After a term is built, drop it when its text has no scalar that is a letter or a number (`scalar.properties.isAlphabetic || scalar.properties.numericType != nil`). The `studyreader` tokenizer splits on everything else, so such a term is a zero-token phrase that would make an AND fail. Applies to negated terms too. Document it in the type comment ("`network +` searches `network`").
3. **Narrow the catch (B21 1).** In `SearchService.search`, return empty results only for an FTS5 syntax error: `DatabaseError` with `resultCode == .SQLITE_ERROR` AND `message` starting with `"fts5:"`. Log it with `Log.database.error("FTS5 rejected the search expression: \(message, privacy: .private)")`. Every other error is rethrown (so "no such table" reaches `SearchModel`, which shows its message). Update the doc comment (remove the NUL example; NUL no longer reaches FTS5).
4. **Merge tie-break (B21 4).** In `run`, sort merged document hits by `(rank, documentId, field.rawValue, unitIndex ?? -1)` (numeric `unitIndex`), not by the string `id`. Keep highlights by `(rank, highlightId)` and notes by `(rank, kind.rawValue, highlightId ?? documentId)`.
5. **Layering note (B21 5).** Add one line to the `SearchService` doc comment: "It reads the FTS tables directly, like a repository; it is the only search code that touches GRDB." No move.

## Acceptance criteria
1. `SearchQueryParserTests/nulScalarsAreDropped`: `"net\u{0}work"` → one term `network`; `"\u{0}"` → no terms; `matchExpression(for: "a\u{0}\"b")` contains no U+0000.
2. `SearchQueryParserTests/punctuationOnlyTermsAreDropped`: `+`, `(*`, `.`, `"..."` → no terms; `matchExpression(for: "network +")` == `"\"network\""`; `matchExpression(for: "+ -x")` == nil.
3. `SearchQueryParserTests/unicodeLineSeparatorsSplitTerms`: `"a\u{2028}b"` and `"a\u{0085}b"` → two terms `a`, `b` (B20 3).
4. The existing `SearchServiceTests/malformedInputsDoNotThrow` gains `+`, `+ -x`, `(*`, and a string with U+0000; each returns without throwing.
5. `SearchServiceTests/negatedTermExcludesAcrossHighlightAndNoteColumns` (B21 2): a highlight whose text has "network" and whose note has "convolutional", and one with "network" only: `network -convolutional` returns only the second in `highlights` and nothing for the first in `notes`. Ends with `FTSIntegrity.check`.
6. `SearchServiceTests/missingTableIsNotSwallowed`: on an in-memory database, `DROP TABLE highlight_fts` (inside `writer.write`), then `search("network")` throws (`#expect(throws:)`).
7. `SearchServiceTests/documentHitsTieBreakNumerically`: two text hits of one document with equal rank in units 2 and 10 come out unit 2 first (build the case so ranks are equal, e.g. identical unit texts).
8. `SearchModelTests/searchErrorShowsMessage` (B22 3): environment from criterion 6 (dropped `highlight_fts`); set `query`, `await searchNow()`; `errorMessage` is non-nil, `results.isEmpty`, `isSearching == false`.
9. Existing `SearchQueryParserTests`, `SearchServiceTests`, `SearchModelTests`, `SearchIndexSyncTests` pass: `./scripts/test.sh StudyReaderTests/SearchQueryParserTests StudyReaderTests/SearchServiceTests StudyReaderTests/SearchModelTests StudyReaderTests/SearchIndexSyncTests`. `./scripts/build.sh` succeeds.

## Out of scope
The top-N snippet optimisation (B21 3, waits for a measurement on a big library on the Mac), moving the SQL into a repository, the stale-result test (needs a service seam), any UI change.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
2026-10-28, implementer data-layer Haiku medium (no reworks), reviewer code-reviewer Sonnet medium: APPROVED, CI green (run 40675061323, 210 tests); deviations (combining-mark test expectations, searchErrorShowsMessage via debounce path, scoped negation) judged legitimate; minor suggestion: add a phrase+combining-mark case to SearchQueryParserTests (backlog)
