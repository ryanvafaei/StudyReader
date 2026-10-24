# T34: Document and category repositories for Phase 1

- **Phase:** 1 (E1.1: F-01, F-11)
- **Agent:** data-layer
- **Depends on:** T29, T33
- **ADRs:** docs/decisions/0012-data-layer-conventions.md (writes, dates, upsert), docs/decisions/0013-schema-migration-policy-v2.md (column-limited updates)
- **Visual check needed:** no

## Goal
Everything the library, import, reader and metadata sheet need from `document` and `category`: lookup by hash, delete with file cleanup, metadata/cover/position/extraction updates, a live library list with category names, highlight counts and tags, and custom category management.

## Files to touch
- `StudyReader/Core/Repositories/DocumentRepository.swift` (modify)
- `StudyReader/Core/Repositories/CategoryRepository.swift` (modify)
- `StudyReader/Core/Models/LibraryItem.swift` (new)
- `StudyReaderTests/CoreTests/DocumentRepositoryTests.swift` (modify: add tests)
- `StudyReaderTests/CoreTests/CategoryRepositoryTests.swift` (modify: add tests)

## Rules for every write in this task
- Updates fetch the record in the same `write` closure, change fields, then call `record.update(db, columns: [...])` with only the changed columns. Never a full `update(db)` (it fires `document_fts_au`, ADR-0013), never `upsert`, never `updateAll` with a bare `Date`.
- A missing row throws `RepositoryError.notFound` (new, below) from updates.
- Every test that writes `document` or `highlight` ends with `try await db.reader.read { try FTSIntegrity.check($0) }`.

## Interfaces to produce
```swift
// Core/Models/LibraryItem.swift
/// One row of the library list (SPEC F-01).
struct LibraryItem: Sendable, Equatable, Identifiable {
    var document: LibraryDocument
    var categoryName: String
    var highlightCount: Int
    var tagIds: [String]          // sorted ascending
    var id: String { document.id }
}

/// Shared by repositories (add to LibraryItem.swift).
enum RepositoryError: Error, Equatable { case notFound }

// DocumentRepository additions
func fetch(fileHash: String) async throws -> LibraryDocument?
/// Deletes the row in one transaction (cascades to documentText, highlight, tags, notes, cards,
/// embeddings and FTS through triggers), then fileStore.deleteDocumentFolder(documentId:).
/// Returns false when no row existed (the folder is still removed).
@discardableResult
func delete(id: String, fileStore: FileStore) async throws -> Bool
/// title and author are trimmed; an empty title throws DocumentEditError.emptyTitle (below).
func updateMetadata(id: String, title: String, author: String, categoryId: String) async throws   // columns title, author, categoryId
func updateCover(id: String, coverPath: String?, coverSource: CoverSource) async throws            // columns coverPath, coverSource
func updatePDFPosition(id: String, position: PDFPosition, progress: Double) async throws           // columns pdfPosition, progress (progress clamped 0...1)
func updateTextPosition(id: String, offset: Int, progress: Double) async throws                     // columns textPosition, progress
func markOpened(id: String, at date: Date) async throws                                             // column lastOpenedAt
func updateExtraction(id: String, status: ExtractionStatus, version: Int) async throws               // columns extractionStatus, extractionVersion
func fetchAllItems() async throws -> [LibraryItem]                 // order as fetchAll(): addedAt desc, title asc
func observeItems() -> AsyncValueObservation<[LibraryItem]>        // same query, live
```
```swift
enum DocumentEditError: Error, Equatable, LocalizedError { case emptyTitle }   // "A title is required."
```
`fetchAllItems` in one `read`: all documents (existing order), `DocumentCategory.fetchAll` into a dictionary by id, `SELECT documentId, COUNT(*) FROM highlight GROUP BY documentId`, and `SELECT documentId, tagId FROM documentTag ORDER BY tagId`. A document whose category row is missing gets `categoryName = ""` (can't happen with the FK, but don't crash).

```swift
// CategoryRepository additions
enum CategoryError: Error, Equatable, LocalizedError {
    case emptyName, nameTooLong, duplicateName, builtinCategory, notFound
    // texts: "Enter a category name." / "Category names can have at most 40 characters." /
    // "A category with this name already exists." / "Built-in categories can't be renamed or deleted." /
    // "This category no longer exists."
}
struct CategoryUsage: Sendable, Equatable, Identifiable {
    var category: DocumentCategory
    var documentCount: Int
    var id: String { category.id }
}
/// Trims; 1–40 characters. Duplicate = any existing name equal case-insensitively (lookup first, ADR-0012).
/// New row: id UUID().uuidString, isBuiltin false, frequency .normal, autoCreateCards true, sortOrder = max + 1.
func create(name: String) async throws -> DocumentCategory
/// Custom categories only. Renaming to the same name with different case is allowed.
func rename(id: String, to name: String) async throws
/// Custom categories only. One transaction: move its documents to BuiltinCategory.other.id, then delete the row.
/// Returns the number of documents moved.
@discardableResult func delete(id: String) async throws -> Int
func observeUsage() -> AsyncValueObservation<[CategoryUsage]>   // categories in fetchAll() order with document counts (0 included)
```
Check the `DocumentCategory` property names in `Core/Models/DocumentCategory.swift` before writing (they equal the column names in ARCHITECTURE §4). Moving documents uses `LibraryDocument.filter(Column("categoryId") == id).updateAll(db, Column("categoryId").set(to: BuiltinCategory.other.id))` (no date involved; `categoryId` isn't indexed, so no FTS trigger fires).

## Tests
`DocumentRepositoryTests` (in-memory `AppDatabase.makeInMemory()` unless stated; documents from `TestData.document`):
- `fetchByHash`: insert two documents; `fetch(fileHash:)` finds each; unknown hash → nil.
- `deleteCascades` (SPEC F-01 AC3): with a `TestFileStore.make()` store (+ `defer remove`): insert a document, create its folder and write `original.pdf` (any bytes) via `originalFileURL(documentId:fileType:)`; insert a `documentText` row, two highlights (`TestData.highlight`) with a tag link (`TestData.tag` + `HighlightTag`), a `DocumentTag`, a `DocumentNote`, a `ReviewCard` for one highlight and a `HighlightEmbedding` (check its initializer in `Core/Models/HighlightEmbedding.swift`). `delete(id:fileStore:)` returns true; every dependent table has 0 rows for that document; the tag row itself remains; the folder no longer exists; `FTSIntegrity.check` passes. A second delete returns false.
- `metadataUpdate` (SPEC F-11 AC2): `updateMetadata` changes title/author/category; `fetch` shows them; a raw FTS query `SELECT rowid FROM document_fts WHERE document_fts MATCH '"newtitleword"'` finds the document and the old title word no longer matches; `FTSIntegrity.check` passes. Empty/whitespace title throws `DocumentEditError.emptyTitle`; unknown id throws `RepositoryError.notFound`.
- `positionAndOpenUpdates`: `updatePDFPosition(position: PDFPosition(pageIndex: 3, offsetY: 120.5), progress: 0.4)`, `updateTextPosition(offset: 42, progress: 1.7)` (stored 1.0), `markOpened(at: TestData.referenceDate)`; fetched values match. Assert with a raw query that `lastOpenedAt` is stored as REAL (`SELECT typeof(lastOpenedAt) …` == "real").
- `positionUpdateDoesNotTouchSearchIndex`: on an in-memory database (a `DatabaseQueue`, so one connection), insert a document, then install a trace: `try await db.writer.write { $0.trace { event in box.withLock { $0.append(event.description) } } }` where `box` is a `Mutex<[String]>` (`import Synchronization`). Call `updatePDFPosition`, `updateTextPosition`, `markOpened`, `updateCover` and `updateExtraction`. Remove the trace (`$0.trace(options: [], nil)`). Expect: at least one traced statement starts with `UPDATE "document" SET`; no traced `UPDATE` statement contains `"title"` or `"author"`; no traced statement contains `document_fts`. Then `FTSIntegrity.check` passes.
- `coverAndExtractionUpdates`: `updateCover(coverPath: "\(id)/cover.png", coverSource: .custom)` and `updateExtraction(status: .done, version: 1)` round-trip.
- `itemsIncludeCountsTagsAndCategory`: two documents in different categories; three highlights on the first; two document tags on the second; `fetchAllItems()` has `highlightCount` 3 and 0, `tagIds` sorted, `categoryName` "Lecture slides" / "Paper".
- `observeItemsEmitsAfterHighlightInsert` (`.timeLimit(.minutes(1))`): first value has count 0; inserting a highlight emits a value with count 1.

`CategoryRepositoryTests`:
- `createRenameDelete`: create "Lab reports" → sortOrder 5, isBuiltin false; rename to "lab Reports" works; rename to "paper" throws `.duplicateName`; create "  " throws `.emptyName`; 41 characters throws `.nameTooLong`; delete with two documents in it returns 2 and they now have `BuiltinCategory.other.id`.
- `builtinsAreProtected`: rename or delete `BuiltinCategory.paper.id` throws `.builtinCategory`; unknown id throws `.notFound`.
- `observeUsageCounts`: first emitted value lists 5 built-ins with counts; after inserting a document in Paper, a value with Paper count 1 arrives.

## Acceptance criteria
1. Delete removes all dependent rows and the stored folder. → test `DocumentRepositoryTests/deleteCascades`
2. Metadata edits persist and update the search index. → test `DocumentRepositoryTests/metadataUpdate`
3. Position, open, cover and extraction updates persist with column-limited writes. → tests `DocumentRepositoryTests/positionAndOpenUpdates`, `positionUpdateDoesNotTouchSearchIndex`, `coverAndExtractionUpdates`
4. The library list has category names, highlight counts and tags, live. → tests `DocumentRepositoryTests/itemsIncludeCountsTagsAndCategory`, `observeItemsEmitsAfterHighlightInsert`
5. Custom categories can be created, renamed and deleted; built-ins can't; delete reassigns to Other. → tests `CategoryRepositoryTests/*`
6. Existing tests pass; every new writing test ends with `FTSIntegrity.check`.

## Out of scope
- Tags on documents (T36 owns `documentTag` writes; tests here insert `DocumentTag` records directly).
- Settings reset when the default category is deleted (T50 UI does it).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, code-reviewer (sonnet, medium): APPROVED. 193 tests pass. Minor: some tests use different data than the spec; FTSIntegrity check missing at end of fetchByHash/observeUsageCounts.
