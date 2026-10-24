# T65: SearchService

- **Phase:** 1 (E1.6: F-12)
- **Agent:** data-layer
- **Model / effort:** sonnet, high (from the first call; treat as escalated: review with code-reviewer effort high; two rejections → ask the user)
- **Depends on:** T44, T64
- **ADRs:** docs/decisions/0014-* (tokenizer), docs/decisions/0013-schema-migration-policy-v2.md (FTS tables and triggers), docs/decisions/0012-data-layer-conventions.md, ARCHITECTURE §8
- **Visual check needed:** no

## Goal
Search every indexed field (SPEC F-12): document text (per PDF page / Markdown section), highlight text, highlight notes, document notes, titles and authors. Results are grouped (Documents, Highlights, Notes), ranked by bm25, with `**`-marked snippets and a location to open, and filtered by tag, category and document type.

## Files to touch
- `StudyReader/Features/Search/SearchService.swift` (new)
- `StudyReader/Features/Search/SearchResults.swift` (new)
- `StudyReader/App/AppEnvironment.swift` (modify: `let searchService: SearchService`)
- `StudyReaderTests/SearchTests/SearchServiceTests.swift`, `StudyReaderTests/SearchTests/SearchIndexSyncTests.swift` (new)

## Interfaces to produce
```swift
struct SearchFilters: Sendable, Equatable {
    var tagId: String? = nil
    var categoryId: String? = nil
    var fileType: FileType? = nil
}

struct DocumentHit: Sendable, Equatable, Identifiable {
    enum Field: String, Sendable { case text, titleOrAuthor }
    var documentId: String
    var title: String
    var field: Field
    var unitIndex: Int?            // PDF page index / Markdown section index for .text, nil for .titleOrAuthor
    var snippet: String            // match wrapped in ** **
    var rank: Double               // bm25, lower is better
    var id: String { "\(documentId)#\(field.rawValue)#\(unitIndex ?? -1)" }
}
struct HighlightHit: Sendable, Equatable, Identifiable {
    var highlightId: String
    var documentId: String
    var documentTitle: String
    var pageIndex: Int?
    var snippet: String
    var rank: Double
    var id: String { highlightId }
}
struct NoteHit: Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable { case highlightNote, documentNote }
    var kind: Kind
    var documentId: String
    var documentTitle: String
    var highlightId: String?       // set for .highlightNote
    var snippet: String
    var rank: Double
    var id: String { "\(kind.rawValue)#\(highlightId ?? documentId)" }
}
struct SearchResults: Sendable, Equatable {
    var documents: [DocumentHit] = []
    var highlights: [HighlightHit] = []
    var notes: [NoteHit] = []
    var isEmpty: Bool { get }
}

struct SearchService: Sendable {
    init(database: AppDatabase)
    /// SearchQueryParser.matchExpression(for: query); nil → empty results. limit applies per group.
    /// Within each group results are ordered by rank ascending, then id. Documents = text hits and title/author
    /// hits merged by rank. Notes = highlight-note and document-note hits merged by rank.
    func search(_ query: String, filters: SearchFilters = SearchFilters(), limit: Int = 50) async throws -> SearchResults
}
```

## SQL (bind `match`, filter values and `limit` as arguments; never interpolate user text)
`<docFilter>` is built from the filters, each part only when set, ANDed:
`d.categoryId = ?`, `d.fileType = ?`, `EXISTS (SELECT 1 FROM documentTag x WHERE x.documentId = d.id AND x.tagId = ?)`.
For highlight hits the tag filter is instead `EXISTS (SELECT 1 FROM highlightTag x WHERE x.highlightId = h.id AND x.tagId = ?)`.

1. Document text:
```sql
SELECT dt.documentId, d.title, dt.unitIndex,
       snippet(documentText_fts, 0, '**', '**', '…', 12) AS snippet, bm25(documentText_fts) AS rank
FROM documentText_fts
JOIN documentText dt ON dt.rowid = documentText_fts.rowid
JOIN document d ON d.id = dt.documentId
WHERE documentText_fts MATCH ? [AND <docFilter>]
ORDER BY rank LIMIT ?
```
2. Titles and authors: same shape over `document_fts` joined `d.rowid = document_fts.rowid`; snippet column `-1` (best column) — use `snippet(document_fts, -1, '**', '**', '…', 12)`.
3. Highlight text: `highlight_fts` joined `h.rowid = highlight_fts.rowid` and `document d ON d.id = h.documentId`, the bound MATCH argument is the Swift string `"{text editedText} : (\(expression))"`, where `expression` is the parser output (every user term is already quoted, so building this argument is safe; it's still bound with `?`, not put into the SQL text); snippet column `-1`.
4. Highlight notes: same join, bound MATCH argument `"note : (\(expression))"`, snippet column 2.
5. Document notes: `documentNote_fts` joined `n.rowid = documentNote_fts.rowid`, `document d ON d.id = n.documentId`, snippet column 0.

Run all five in one `read`. Map rows to the hit types. If the system SQLite rejects a column filter applied to a parenthesized expression containing `NOT`, stop and report BLOCKED with the exact error (the architect will choose a fallback).

## Tests
`SearchServiceTests` (in-memory environment; insert documents, `documentText` rows via `DocumentTextRepository.replaceUnits`, highlights, notes, tags directly):
- `findsDocumentText`: a PDF with page 2 containing "backpropagation" → one `DocumentHit` (`field .text`, `unitIndex 2`, snippet contains `**backpropagation**`).
- `findsTitlesAndAuthors`: title "Neural Networks", author "Ada Lovelace" → hits for "neural" and "lovelace" with `field .titleOrAuthor`.
- `findsHighlights`: highlight text "gradient descent" → `HighlightHit` with `pageIndex`.
- `findsNotes` (SPEC F-09 AC2): a highlight note "remember the chain rule" → `NoteHit(kind: .highlightNote, highlightId:)`, and it is not in `highlights`; a document note "exam on Friday" → `.documentNote`.
- `phrasePrefixExclusion`: "\"chain rule\"" matches only the phrase; "backprop*" matches "backpropagation"; "network -convolutional" excludes the document whose text has both.
- `normalizedMatches` (ADR-0014): document text containing `SearchSamples.photosynthesisSoftHyphen` and `SearchSamples.findLigature` is found by "photosynthesis" and "find"; "cafe" finds "Café".
- `filtersApply`: tag (document tag for document hits, highlight tag for highlight hits), category and file type filters each narrow results; combined filters intersect.
- `rankingOrdersByBm25`: a document mentioning "kernel" five times ranks above one mentioning it once.
- `emptyOrNegativeOnlyQuery`: "" and "-x" → empty results, no SQL error.
- Each test ends with `FTSIntegrity.check`.
`SearchIndexSyncTests` (SPEC F-12 AC3):
- `documentTitleChange`: `updateMetadata` → new title found, old not.
- `documentDelete`: delete → no hits of any kind for its text, highlights or notes.
- `highlightCreateUpdateDelete`: insert → found; `updateNote` → note hit appears; color change doesn't change results; delete → gone.
- `documentNoteUpsert`: save note twice → only the latest body matches.
- `reExtractionReplacesText`: `replaceUnits` with new text → old words no longer match.
- Each ends with `FTSIntegrity.check`.

## Acceptance criteria
1. Each indexed field is searchable and returns the right location. → tests `SearchServiceTests/*` (SPEC F-12 AC1)
2. Notes appear in search results. → test `SearchServiceTests/findsNotes` (SPEC F-09 AC2)
3. The index stays in sync on create/update/delete. → tests `SearchIndexSyncTests/*` (SPEC F-12 AC3)
4. Filters and ranking work; user text never reaches SQL unquoted (code review).

## Out of scope
- UI (T66), in-document find (T67), the 200 ms performance target (measured manually in the phase's visual check, not a unit test).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
