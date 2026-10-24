# T68: Highlight browse query (filters and sorts for the highlights browser)

- **Phase:** 1 (E1.7: F-13 data)
- **Agent:** data-layer
- **Depends on:** T35, T36
- **ADRs:** docs/decisions/0012-data-layer-conventions.md (dates in SQL: `.databaseUnixSeconds`), ARCHITECTURE §4
- **Visual check needed:** no

## Goal
One query for the highlights browser (SPEC F-13): every highlight across the library with its document title, category and tags, filtered by document, category, tag (any/all), color, has note, view type and date range, sorted by created date, document and position, or color; as a one-shot fetch and a live observation.

## Files to touch
- `StudyReader/Core/Repositories/HighlightBrowseQuery.swift` (new: types + `HighlightRepository` extension)
- `StudyReaderTests/CoreTests/HighlightBrowseQueryTests.swift` (new)

## Interfaces to produce
```swift
struct HighlightBrowserFilter: Sendable, Equatable {
    var documentIds: Set<String> = []            // empty = all
    var categoryIds: Set<String> = []
    var tagIds: Set<String> = []
    var tagMode: TagMatchMode = .any             // ColumnValues.swift
    var colors: Set<HighlightColor> = []
    var hasNote: Bool? = nil                     // true: TRIM(note) <> ''; false: TRIM(note) = ''
    var views: Set<ReaderViewKind> = []
    var createdFrom: Date? = nil                 // inclusive
    var createdBefore: Date? = nil               // exclusive
}
enum HighlightBrowserSort: String, Sendable, CaseIterable {
    case createdNewest        // createdAt DESC, id ASC
    case documentPosition     // document title COLLATE NOCASE ASC, documentId ASC, positionKey ASC, createdAt ASC
    case color                // color ASC, createdAt DESC, id ASC
}
struct HighlightListItem: Sendable, Equatable, Identifiable {
    var highlight: Highlight
    var documentTitle: String
    var categoryId: String
    var tagIds: [String]                          // sorted
    var tagNames: [String]                        // sorted case-insensitively
    var id: String { highlight.id }
}

extension HighlightRepository {
    func browse(filter: HighlightBrowserFilter, sort: HighlightBrowserSort) async throws -> [HighlightListItem]
    func observeBrowse(filter: HighlightBrowserFilter, sort: HighlightBrowserSort) -> AsyncValueObservation<[HighlightListItem]>
}
```
Implementation (one `read`, or one tracking closure):
- Base: `SELECT h.*, d.title AS documentTitle, d.categoryId FROM highlight h JOIN document d ON d.id = h.documentId WHERE <conditions> ORDER BY <sort>`. Fetch `Highlight` rows with GRDB (`Highlight.fetchAll(db, sql:arguments:)` using a row adapter, or fetch `Row`s and decode `Highlight(row:)` plus the two extra columns; your choice, keep it simple).
- Conditions (only for set fields; every value bound as an argument):
  - `h.documentId IN (…)`, `d.categoryId IN (…)`, `h.color IN (…)` (raw Ints), `h.view IN (…)` (raw strings);
  - tags any: `EXISTS (SELECT 1 FROM highlightTag t WHERE t.highlightId = h.id AND t.tagId IN (…))`;
  - tags all: `(SELECT COUNT(DISTINCT t.tagId) FROM highlightTag t WHERE t.highlightId = h.id AND t.tagId IN (…)) = <count>` (bind the count);
  - `TRIM(h.note) <> ''` / `= ''`;
  - `h.createdAt >= ?` with `createdFrom.databaseUnixSeconds`, `h.createdAt < ?` with `createdBefore.databaseUnixSeconds` (never a bare `Date`, ADR-0012).
- Tags for the result: `SELECT t.highlightId, g.id, g.name FROM highlightTag t JOIN tag g ON g.id = t.tagId WHERE t.highlightId IN (…)` (or for all highlights when unfiltered), grouped in Swift.
- Build the SQL with GRDB's `SQL` literal interpolation or `SQLRequest` with arguments; never string-concatenate values.

## Tests (`HighlightBrowseQueryTests`, in-memory; fixture: 2 documents (categories Lecture slides, Paper), 6 highlights covering every color, both views (.pdf, .markdown), notes on 2, tags (h1: a,b; h2: a; h3: b), createdAt spread over 3 days)
- `filterDocument`, `filterCategory`, `filterTagAny` (a or b → h1, h2, h3), `filterTagAll` (a and b → h1), `filterColor`, `filterHasNote` (true and false), `filterView`, `filterDateRange` (from day 2 inclusive, before day 3 exclusive).
- `filtersCombine`: category + color + has note.
- `sortCreatedNewest`, `sortDocumentPosition`, `sortColor`.
- `itemsCarryTitleCategoryTags`: titles, categoryId and sorted tag names are right.
- `observeBrowseEmits` (`.timeLimit(.minutes(1))`): changing a highlight's color emits a new list.
- `datesAreBoundAsNumbers`: a filter with `createdFrom` far in the future returns nothing, and one far in the past returns all (guards the TEXT-binding bug, ADR-0012).

## Acceptance criteria
1. Every filter and sort works and they combine. → tests `HighlightBrowseQueryTests/filter*`, `sort*`, `filtersCombine`
2. Items carry document title, category and tags, live. → tests `itemsCarryTitleCategoryTags`, `observeBrowseEmits`
3. Dates are bound as Unix seconds. → test `datesAreBoundAsNumbers`

## Out of scope
- Mastery status filter (Phase 2), UI and bulk actions (T69).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
