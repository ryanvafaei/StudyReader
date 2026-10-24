# T38: HighlightService: create, undo, edit, delete

- **Phase:** 1 (E1.4: F-06, F-08)
- **Agent:** data-layer
- **Depends on:** T35, T36, T37
- **ADRs:** ARCHITECTURE §5 (anchors, positionKey), docs/decisions/0012-data-layer-conventions.md (dates)
- **Visual check needed:** no

## Goal
One service the readers call to turn a selection or snapshot into a stored highlight, undo an auto-highlight with ⌘Z, and change or delete highlights. Engines compute anchors and position keys; this service stores them with fresh IDs and dates.

## Files to touch
- `StudyReader/Features/Annotations/HighlightService.swift` (new)
- `StudyReader/App/AppEnvironment.swift` (modify: add `let highlightService: HighlightService`)
- `StudyReaderTests/AnnotationsTests/HighlightServiceTests.swift` (new)

## Interfaces to produce
```swift
/// What a reader engine hands over for a text selection. view is .pdf or .markdown in Phase 1.
struct NewTextHighlight: Sendable, Equatable {
    var documentId: String
    var view: ReaderViewKind
    var anchor: HighlightAnchor          // .pdf or .text
    var text: String                     // plain selected text
    var richText: String                 // F-07 Markdown subset (escaped plain text for PDF view in Phase 1)
    var pageIndex: Int?                  // first page for PDF; nil for Markdown
    var positionKey: Double
    var color: HighlightColor
}

/// A snapshot (F-08). pngData is already rendered (SnapshotService, T61).
struct NewImageHighlight: Sendable, Equatable {
    var documentId: String
    var pageIndex: Int
    var rect: CGRectCodable              // page space, already clipped
    var positionKey: Double
    var color: HighlightColor
    var pngData: Data
}

enum HighlightServiceError: Error, Equatable, LocalizedError {
    case emptySelection                  // "Select some text to highlight."
    case snapshotWriteFailed             // "The snapshot couldn't be saved."
}

actor HighlightService {
    init(highlights: HighlightRepository, tags: TagRepository, fileStore: FileStore, now: any Now)

    /// Stores text as given; if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty → .emptySelection.
    /// Creates Highlight(id: UUID().uuidString, kind: .text, createdAt = updatedAt = now(), …) and inserts it.
    /// isAuto == true remembers the id as the undoable auto-highlight; any other call below forgets it.
    func createText(_ new: NewTextHighlight, isAuto: Bool) async throws -> Highlight
    /// Writes pngData to fileStore.snapshotURL(documentId:highlightId:) (creating snapshots/), then inserts
    /// kind .image, view .pdf, anchor .image(ImageAnchor(pageIndex:rect:)), imagePath = relativePath(for:).
    /// If the insert fails, deletes the PNG and rethrows. If writing fails, throws .snapshotWriteFailed.
    func createImage(_ new: NewImageHighlight) async throws -> Highlight
    /// Deletes the remembered auto-highlight and returns its id; nil if there is none (then does nothing).
    func undoLastAutoHighlight() async throws -> String?
    func setColor(id: String, color: HighlightColor) async throws
    func delete(id: String) async throws
    func delete(ids: [String]) async throws
    func setColor(ids: [String], color: HighlightColor) async throws
}
```
- Every date comes from `now()`.
- `setColor`/`delete` forget the remembered auto-highlight (so ⌘Z only works right after creating it). Notes go through `NoteEditorModel` (T37) and tags through `TagRepository`; they don't need to go through this service.
- The UI registers ⌘Z with the window's `UndoManager` and calls `undoLastAutoHighlight()` (T59, T60). Nothing here imports AppKit.

## Tests (`HighlightServiceTests`, `AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))`, remove the env folder in `defer`; a document inserted first)
- `autoHighlightUndo` (SPEC F-06 AC1): `createText(new, isAuto: true)` → row exists with color from `new`, `createdAt == referenceDate`; `undoLastAutoHighlight()` returns its id and the row is gone; a second call returns nil.
- `undoOnlyRightAfter`: create auto h1, then `setColor(id: h1, .blue)` → `undoLastAutoHighlight()` returns nil and h1 still exists. Create auto h2, then create non-auto h3 → undo returns nil.
- `rejectsEmptySelection`: text `"  \n"` throws `.emptySelection`; no row.
- `createImageWritesPNG`: `TestFileStore`-backed env (`inMemory` already has a temp FileStore); `createImage` with 8 bytes of PNG signature data → file exists at `snapshotURL`, `imagePath == "\(docId)/snapshots/\(id).png"`, `kind == .image`, `view == .pdf`, anchor is `.image` with the same rect.
- `deleteAndColorBulk`: two highlights; `setColor(ids:)` then `delete(ids:)`; rows updated then gone.
- All tests end with `FTSIntegrity.check`.

## Acceptance criteria
1. An auto-highlight can be undone right after creation, and only then. → tests `HighlightServiceTests/autoHighlightUndo`, `undoOnlyRightAfter`
2. Empty selections are rejected. → test `HighlightServiceTests/rejectsEmptySelection`
3. Snapshots are written to the FileStore path and linked by `imagePath`. → test `HighlightServiceTests/createImageWritesPNG`
4. Bulk color/delete work. → test `HighlightServiceTests/deleteAndColorBulk`

## Out of scope
- Anchors and positionKey math (T56, T57), PNG rendering (T61), UI (T59–T63).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, code-reviewer (sonnet, medium): APPROVED. All spec assertions present; 215 tests pass. Minor: no test for PNG cleanup on insert failure; undoLastAutoHighlight clears the id before delete; snapshotURL errors not mapped to snapshotWriteFailed.
