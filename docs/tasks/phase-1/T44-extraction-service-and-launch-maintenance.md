# T44: ExtractionService, DocumentTextRepository and launch maintenance

- **Phase:** 1 (E1.1/E1.6: F-02 step 5, F-12 indexing; SPEC §4 reliability)
- **Agent:** data-layer
- **Depends on:** T41, T42, T43
- **ADRs:** docs/decisions/0016-import-pipeline-and-stored-files.md (order, crash cleanup, extraction), docs/decisions/0013-schema-migration-policy-v2.md, ARCHITECTURE §3, §6, §13
- **Visual check needed:** no

## Goal
Fill `documentText` in the background after import (PDF pages via `PDFTextExtractor`, Markdown sections via `MarkdownRenderer`), so search finds document text; re-queue unfinished or outdated extractions at launch; remove folders left by interrupted imports before the library appears. Wire `ImportService` and `ExtractionService` into `AppEnvironment`.

## Files to touch
- `StudyReader/Core/Repositories/DocumentTextRepository.swift` (new)
- `StudyReader/Features/Extraction/ExtractionService.swift` (new)
- `StudyReader/Features/Extraction/LibraryMaintenance.swift` (new)
- `StudyReader/App/AppEnvironment.swift` (modify)
- `StudyReader/App/AppLaunchModel.swift` (modify: start background work after `.ready`)
- `StudyReaderTests/ExtractionTests/ExtractionServiceTests.swift`, `StudyReaderTests/ExtractionTests/LibraryMaintenanceTests.swift` (new)

## Interfaces to produce
```swift
struct DocumentTextRepository: Sendable {
    init(database: AppDatabase)
    /// One transaction: return false (writing nothing) if the document row is gone; otherwise delete its
    /// documentText rows, insert `units`, and set extractionStatus .done + extractionVersion `version`
    /// with record.update(db, columns: ["extractionStatus", "extractionVersion"]). Returns true.
    @discardableResult
    func replaceUnits(_ units: [DocumentText], documentId: String, version: Int) async throws -> Bool
    func markFailed(documentId: String) async throws          // extractionStatus .failed (column-limited)
    func fetchUnits(documentId: String) async throws -> [DocumentText]   // ORDER BY unitIndex
}

actor ExtractionService: ExtractionQueue {
    init(database: AppDatabase, fileStore: FileStore)
    /// Adds the id unless it is queued or running; starts the worker if idle. Returns immediately.
    func enqueue(documentId: String)
    /// Returns once the queue is empty and the worker is idle (tests, and nothing else).
    func waitUntilIdle() async
    /// Extracts one document now. Throws on file errors; marks .failed before rethrowing.
    func extract(documentId: String) async throws
}

struct LibraryMaintenance: Sendable {
    init(database: AppDatabase, fileStore: FileStore)
    /// Synchronous (runs in the launch factory, off the main actor): removes Documents/<id> folders
    /// (FileStore.documentFolderIds(), canonical only) that have no document row. Returns removed ids, sorted.
    func removeOrphanFolders() throws -> [String]
    /// Ids with extractionStatus 'pending', or 'done' and extractionVersion below the current version for
    /// their type (pdf: PDFTextExtractor.version, markdown: MarkdownRenderer.version). Failed ones aren't retried.
    func documentIdsNeedingExtraction() async throws -> [String]
}
```
Extraction of one document:
- Fetch the row (`DocumentRepository.fetch(id:)`); gone → return. Resolve `fileStore.url(forRelativePath: storedPath)`; nil or missing file → `markFailed`, throw.
- PDF: `try await Task.detached { try PDFTextExtractor.extract(fileAt: url) }.value`; `startOffsets`; one `DocumentText(documentId:, unitIndex: page.pageIndex, startOffset:, text: page.text, runs: page.runs.isEmpty ? nil : page.runs)` per page; version `PDFTextExtractor.version`.
- Markdown: read UTF-8, `MarkdownRenderer.render(MarkdownDocumentSource(markdown:, documentId:, fileStore:))` inside `Task.detached`, returning only `(string, sections)`; one row per section: `unitIndex` = section index, `startOffset` = `section.location`, `text` = the substring, `runs` nil; version `MarkdownRenderer.version`. Sections come from T43 as is (ARCHITECTURE §6): a new section at each H1 or H2 heading, text before the first one is section 0 starting at offset 0, sections partition the string exactly, so the row texts concatenate to the rendered string. An empty document has no sections: write zero rows and still mark the document `.done` with the current version.
- `replaceUnits(...)`. Errors → `markFailed` (if the row still exists), log the id, continue with the next queued id.
- Logging (`Log.files` or a new `Log.extraction` category): ids and counts only.

`AppEnvironment` changes:
- New properties: `documentTextRepository`, `extractionService: ExtractionService`, `importService: ImportService` (built in `init` from the existing repositories, `CoverService(fileStore:documents:)`, `settingsStore`, `now`, and `extractionService` as its queue).
- `make(fileStore:now:settingsStore:)` (the on-disk path used by `live()`): after the database opens, `let removed = try? LibraryMaintenance(database:fileStore:).removeOrphanFolders()` and log the count. Never in `inMemory`.
- `func startBackgroundWork() async`: `for id in (try? await LibraryMaintenance(...).documentIdsNeedingExtraction()) ?? [] { await extractionService.enqueue(documentId: id) }`.
- `AppLaunchModel.start()`: after `state = .ready(environment)`, `Task { await environment.startBackgroundWork() }`.

## Tests
`ExtractionServiceTests` (`AppEnvironment.inMemory()` + remove folder in `defer`; documents imported with `env.importService.importItems(at:interaction:)` using an always-yes stub interaction, defined locally):
- `extractsPDFPages`: import `plainMultiPage(pageCount: 3)`; `await env.extractionService.waitUntilIdle()`; 3 `documentText` rows with unitIndex 0…2, startOffsets `[0, len0 + 2, len0 + len1 + 4]`; status `.done`, version `PDFTextExtractor.version`; a raw FTS query on `documentText_fts` for `"quick"` returns 3 rows.
- `extractsMarkdownSections`: import a Markdown file `"Intro\n\n# A\n\ntext\n\n## B\n\nmore"` → 3 rows whose texts concatenate to `MarkdownRenderer.render(...).string`; status `.done`, version `MarkdownRenderer.version`.
- `emptyMarkdownHasNoRows`: import an empty `.md` file (0 bytes, or only front matter) → 0 `documentText` rows; status `.done`, version `MarkdownRenderer.version`.
- `missingFileMarksFailed`: insert a row by hand whose `storedPath` file doesn't exist; `extract` throws and status becomes `.failed`.
- `reExtractionReplacesRows`: extracting the same document twice leaves the same row count (no duplicates).
- `deletedDocumentIsSkipped`: enqueue, delete the document before `waitUntilIdle`; no rows, no error escapes.
- All end with `FTSIntegrity.check`.

`LibraryMaintenanceTests`:
- `removesOrphanFolders`: `TestFileStore.make()` (+ remove) with `AppDatabase.makeShared`; one document row with a folder, one orphan folder (canonical id, no row), one non-canonical folder `"keep-me"`; `removeOrphanFolders()` returns `[orphanId]`; the document folder and `"keep-me"` remain.
- `findsPendingAndOutdated`: rows: pending pdf; done pdf at `PDFTextExtractor.version`; done pdf at version 0; failed markdown; done markdown at version 0 → returns the pending pdf, the version-0 pdf and the version-0 markdown (sorted).
- `launchMakeSweepsOrphans`: create an orphan folder in a store, then `AppEnvironment.make(fileStore:)` → the folder is gone.

## Acceptance criteria
1. Imported PDFs and Markdown files get `documentText` rows and become searchable, in the background. → tests `ExtractionServiceTests/extractsPDFPages`, `extractsMarkdownSections`
2. Failures are marked and don't stop the queue; re-extraction replaces rows; deleted documents are skipped. → tests `missingFileMarksFailed`, `reExtractionReplacesRows`, `deletedDocumentIsSkipped`
3. Interrupted imports are cleaned up at launch; pending and outdated extractions are re-queued. → tests `LibraryMaintenanceTests/*`
4. `AppEnvironment` exposes `importService`, `extractionService`, `documentTextRepository`; full suite passes.

## Out of scope
- Retry button UI (T47 calls `extractionService.enqueue`). Search queries (T65).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, code-reviewer (sonnet, medium): APPROVED. All spec assertions present; 290 tests pass; orphan sweep safe (make() only). Minor: no test that inMemory() skips the sweep; startBackgroundWork swallows errors without logging.
