# T78: Highlight, tag and export queries: private writer, batch tag names, one-snapshot export reads

- **Phase:** 1 (end-of-phase backlog pass, `docs/BACKLOG.md` B25, B30 (1)(2)(3)(5 doc comment), B16 (3) repository part, B33 (5); SPEC F-06, F-13, F-21)
- **Agent:** data-layer
- **Depends on:** none (T35, T36, T68, T70 are done)
- **ADRs:** ADR-0012 (data-layer conventions), ADR-0018
- **Visual check needed:** no
- **UI tests:** none (unit tests only)

## Goal
Tidy the repository layer that the browser, the side panel and the export read: `HighlightRepository.writer` goes back to private, the side panel gets one batched and observable "tag names by highlight" query instead of one fetch per row, and `ExportRepository` reads everything for one export in a single database snapshot without loading the whole library or fetching documents one by one.

## Files to touch
- `StudyReader/Core/Repositories/HighlightRepository.swift` (modify)
- `StudyReader/Core/Repositories/HighlightBrowseQuery.swift` (modify)
- `StudyReader/Core/Repositories/TagRepository.swift` (modify)
- `StudyReader/Core/Repositories/ExportRepository.swift` (modify)
- `StudyReaderTests/CoreTests/HighlightBrowseQueryTests.swift`, `StudyReaderTests/CoreTests/TagRepositoryTests.swift`, `StudyReaderTests/ExportTests/ExportRepositoryTests.swift` (modify)

## Interfaces to produce
```swift
// HighlightBrowseQuery.swift: no longer private; internal to the module, used by HighlightRepository and ExportRepository.
enum HighlightBrowseSQL {
    /// `onlyIds` nil: every highlight matching `filter`; non-nil: additionally `h.id IN (onlyIds)` (bound arguments;
    /// an empty set returns []).
    static func items(_ db: Database, filter: HighlightBrowserFilter, sort: HighlightBrowserSort,
                      onlyIds: Set<String>? = nil) throws -> [HighlightListItem]
}

// TagRepository.swift
/// Tag names of every highlight of the document that has at least one tag, keyed by highlight id, names sorted
/// case-insensitively (same order as HighlightListItem.tagNames). One query.
func tagNamesByHighlight(inDocument documentId: String) async throws -> [String: [String]]
/// Live version; the first element is the current value. Tracks highlight, highlightTag and tag.
func observeTagNamesByHighlight(inDocument documentId: String) -> AsyncValueObservation<[String: [String]]>
```

## What to do
1. **B25 1.** Move `browse(filter:sort:)` and `observeBrowse(filter:sort:)` from the extension in `HighlightBrowseQuery.swift` into `HighlightRepository.swift` (same signatures and doc comments) and make `writer` `private` again. `HighlightBrowseQuery.swift` keeps the filter, sort, list item and `HighlightBrowseSQL` (now internal, see Interfaces). Add `onlyIds` to `items` as specified (apply it in both the row query and the tag query).
2. **B16 3.** Add the two `TagRepository` methods above (one SQL query joining `highlight`, `highlightTag`, `tag` with `h.documentId = ?`). No N+1.
3. **B30 1–3.** In `ExportRepository`:
   - `content(for:)` runs ONE `writer.read` that computes the scope name, the browse filter, the items (`HighlightBrowseSQL.items(db, filter:, sort: .documentPosition)`) and assembles the content. `content(forHighlightIds:scopeName:)` does the same with `onlyIds: Set(ids)` (no in-memory filtering of the whole library).
   - Make `assemble` a `static` function taking `db`. Fetch the needed documents in one query (`LibraryDocument.filter(keys: ids)`), and for note-only documents of a category filter in SQL (no per-document `fetchOne` in a loop). Output (order, content) must stay byte-identical: the export goldens must not change.
4. **B30 5 (doc comment only).** On `observeChangeToken()`: "The digest uses `Hasher`, which is seeded per process: compare tokens only within one app run."
5. **B33 5.** Add a unit test for `fetchThemedReviews()` (see criteria). No production change.

## Acceptance criteria
1. `HighlightRepository.writer` is `private` (reviewer checks); every existing `HighlightBrowseQueryTests` test passes unchanged.
2. `HighlightBrowseQueryTests/onlyIdsLimitsTheItems`: three highlights; `items(db, filter: HighlightBrowserFilter(), sort: .documentPosition, onlyIds: [id1, id3])` → exactly those two with their tags; `onlyIds: []` → [].
3. `HighlightBrowseQueryTests/observeBrowseFollowsTagAndDocumentChanges` (B25 2): with an observation running, (a) adding a tag to a highlight emits an item whose `tagNames` contain it; (b) moving the highlight's document to another category emits an item with the new `categoryId`. Bounded waits.
4. `TagRepositoryTests/tagNamesByHighlightInDocument`: document A with h1 (tags "beta", "Alpha") and h2 (no tags), document B with h3 (tag "beta") → for A: `[h1: ["Alpha", "beta"]]` (h2 absent); B's highlight not included.
5. `TagRepositoryTests/observeTagNamesByHighlightEmitsOnRename`: renaming a tag emits the new name for h1; removing the link emits a dictionary without h1.
6. `ExportRepositoryTests/contentForHighlightIdsReadsOnlyThose`: library with 3 documents and 5 highlights; `content(forHighlightIds: [two ids from different documents], scopeName: "x")` → exactly 2 documents, each with its one highlight and its document note.
7. `ExportRepositoryTests/fetchThemedReviewsOrdersByName` (B33 5): themed reviews "beta", "Alpha", "gamma" → names in order Alpha, beta, gamma.
8. All `ExportRendererTests` golden tests and existing `ExportRepositoryTests`, `TagRepositoryTests`, `HighlightRepositoryTests` pass; tests that write FTS-indexed tables end with `FTSIntegrity.check`. `./scripts/test.sh StudyReaderTests/HighlightBrowseQueryTests StudyReaderTests/TagRepositoryTests StudyReaderTests/ExportRepositoryTests StudyReaderTests/ExportRendererTests StudyReaderTests/HighlightRepositoryTests`. `./scripts/build.sh` succeeds.

## Out of scope
The side panel using the new tag observation (T82), any renderer change (T80), schema changes (no `v3`), `SampleLibrary` (T84).

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
2026-10-28, implementer data-layer Haiku medium (no reworks), reviewer code-reviewer Sonnet medium: APPROVED, CI green (run 40679523642, 645 tests, export goldens unchanged); deviations (existing six-highlight seed, fifth highlight added in contentForHighlightIdsReadsOnlyThose) accepted
