# T35: HighlightRepository

- **Phase:** 1 (E1.4: F-06, F-08 data)
- **Agent:** data-layer
- **Depends on:** T34
- **ADRs:** docs/decisions/0012-data-layer-conventions.md, docs/decisions/0013-schema-migration-policy-v2.md, ARCHITECTURE §4–§5
- **Visual check needed:** no

## Goal
All reads and writes of the `highlight` table for the readers, popover and panel: insert, per-document list (live), color/note/anchor updates, delete with snapshot file cleanup, and bulk color/delete for the browser.

## Files to touch
- `StudyReader/Core/Repositories/HighlightRepository.swift` (new)
- `StudyReader/App/AppEnvironment.swift` (modify: add `let highlightRepository: HighlightRepository`, built in `init`)
- `StudyReaderTests/CoreTests/HighlightRepositoryTests.swift` (new)

## Rules
- Updates fetch the record in the same `write`, change fields, set `updatedAt`, and call `record.update(db, columns: [...])` listing only changed columns plus `updatedAt`. Never full `update(db)`, never `upsert`.
- `updateColor` and `updateAnchor` don't list `text`, `editedText` or `note`, so `highlight_fts_au` doesn't fire. `updateNote` lists `note` (it must re-index).
- Missing rows throw `RepositoryError.notFound` (T34).
- Every writing test ends with `FTSIntegrity.check`.

## Interfaces to produce
```swift
struct HighlightRepository: Sendable {
    init(database: AppDatabase)

    /// One transaction: insert the highlight, then a HighlightTag per tag id (duplicates in tagIds ignored).
    func insert(_ highlight: Highlight, tagIds: [String] = []) async throws
    func fetch(id: String) async throws -> Highlight?
    /// Ordered by positionKey asc, then createdAt asc, then id asc.
    func fetchForDocument(_ documentId: String) async throws -> [Highlight]
    func observeForDocument(_ documentId: String) -> AsyncValueObservation<[Highlight]>
    func observeHighlight(id: String) -> AsyncValueObservation<Highlight?>

    func updateColor(id: String, color: HighlightColor, at date: Date) async throws            // color, updatedAt
    func updateNote(id: String, note: String, at date: Date) async throws                      // note, updatedAt (note stored as given)
    /// Re-anchoring result (ARCHITECTURE §5.3).
    func updateAnchor(id: String, anchor: HighlightAnchor, positionKey: Double,
                      status: AnchorStatus, at date: Date) async throws                        // anchor, positionKey, anchorStatus, updatedAt

    /// Deletes the row (cascades), then removes the snapshot file if imagePath resolves via
    /// fileStore.url(forRelativePath:). A missing file is not an error. Returns false if no row.
    @discardableResult func delete(id: String, fileStore: FileStore) async throws -> Bool
    /// One transaction for the rows; then file cleanup per row. Returns the number deleted.
    @discardableResult func delete(ids: [String], fileStore: FileStore) async throws -> Int
    /// One transaction; unknown ids are skipped. Returns the number updated.
    @discardableResult func updateColor(ids: [String], color: HighlightColor, at date: Date) async throws -> Int
}
```
The browser query (filters, sorts, list items) is T68, in a separate file.

## Tests (`HighlightRepositoryTests`, in-memory database; a document inserted first with `TestData.document`)
- `insertAndFetchForDocument`: three highlights with positionKeys 30, 10, 20 (and two with equal key and different createdAt) come back sorted by positionKey, then createdAt.
- `insertWithTags`: insert with `tagIds: [a, b, a]` → two `HighlightTag` rows.
- `updates` (SPEC F-06 AC5): `updateColor` → `.green`, `updateNote` → "Remember this", `updateAnchor` (new `TextAnchor` start 5, positionKey 5, status `.orphaned`); each persists on fetch with the new `updatedAt` (use `TestData.referenceDate.addingTimeInterval(60)`); `createdAt` unchanged. Unknown id throws `RepositoryError.notFound`. A raw FTS query on `highlight_fts` for the note word finds the highlight after `updateNote`. `FTSIntegrity.check` passes.
- `deleteRemovesSnapshotFile`: `TestFileStore.make()` (+ `defer remove`); an image highlight (`kind: .image`, `view: .pdf`, anchor `.image(ImageAnchor(pageIndex: 0, rect: CGRectCodable(x: 0, y: 0, width: 20, height: 20)))`, `imagePath` = `"\(docId)/snapshots/\(hlId).png"`), with a file written at `fileStore.snapshotURL(documentId:highlightId:)`. `delete(id:fileStore:)` returns true, the row and file are gone. Deleting a text highlight whose `imagePath` is nil works.
- `bulkColorAndDelete`: three highlights; `updateColor(ids: [h1, h2, "missing"], …)` returns 2; `delete(ids: [h2, h3], …)` returns 2; h1 remains.
- `observeForDocumentEmits` (`.timeLimit(.minutes(1))`): first value empty, insert → value with one highlight; `updateColor` → value with the new color.

## Acceptance criteria
1. Popover actions (color, note) and re-anchoring persist immediately. → test `HighlightRepositoryTests/updates`
2. Per-document order is positionKey, createdAt, id. → test `HighlightRepositoryTests/insertAndFetchForDocument`
3. Deleting an image highlight removes its PNG. → test `HighlightRepositoryTests/deleteRemovesSnapshotFile`
4. Tags are linked on insert; bulk color and delete work. → tests `insertWithTags`, `bulkColorAndDelete`
5. Live per-document lists update. → test `observeForDocumentEmits`
6. `AppEnvironment` exposes `highlightRepository`; full suite passes.

## Out of scope
- Creating anchors (T56/T57), the service layer (T38), the browser query (T68), tag editing (T36).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, code-reviewer (sonnet, medium): CHANGES REQUESTED. Tests miss spec assertions: AC2 ordering (3 keys + createdAt tie-break), highlight_fts check after updateNote and distinct updatedAt, updateColor step in observeForDocumentEmits, delete(id:) of a text highlight.
- 2026-10-24, code-reviewer (sonnet, high): APPROVED. Tests now cover all four findings and would catch broken ordering/FTS re-index (judged by reading, no mutations); 199 tests pass.
