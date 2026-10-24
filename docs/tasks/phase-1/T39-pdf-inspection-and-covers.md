# T39: PDF import inspection, cover rendering and CoverService

- **Phase:** 1 (E1.1: F-02, F-11)
- **Agent:** pdf-engine
- **Depends on:** T34
- **ADRs:** docs/decisions/0016-import-pipeline-and-stored-files.md (read in full; the encrypted-PDF bullet was confirmed by the user, Q1), ARCHITECTURE §3 (PDFKit threading), §13
- **Visual check needed:** no

## Goal
PDF work for import and the metadata sheet, all off the main actor with its own `PDFDocument` per call: open/unlock/metadata checks, writing an unlocked copy of a password-protected PDF, rendering page covers, converting a chosen image to the cover PNG, and a `CoverService` that applies cover changes to the stored files and the `document` row.

## Files to touch
- `StudyReader/Features/Library/Import/PDFImportInspector.swift` (new)
- `StudyReader/Features/Library/Covers/CoverRenderer.swift` (new)
- `StudyReader/Features/Library/Covers/CoverService.swift` (new)
- `StudyReaderTests/LibraryTests/PDFImportInspectorTests.swift`, `StudyReaderTests/LibraryTests/CoverTests.swift` (new)

## Interfaces to produce
```swift
struct PDFInfo: Sendable, Equatable {
    var pageCount: Int
    var title: String?            // PDFDocumentAttribute.titleAttribute, nil if absent
    var author: String?           // .authorAttribute
    var isEncrypted: Bool         // document.isEncrypted
}
enum PDFInspectionResult: Sendable, Equatable {
    case ok(PDFInfo)
    case locked                   // needs a password, or the given one is wrong
    case damaged                  // PDFDocument(url:) is nil, or pageCount == 0
}
enum PDFImportInspector {
    /// Opens its own PDFDocument(url:). If isLocked: nil password → .locked; unlock(withPassword:) false → .locked.
    static func inspect(fileAt url: URL, password: String?) -> PDFInspectionResult
    /// Unlocks with password and writes the document to destination with PDFDocument.write(to:) (no options,
    /// so the copy isn't encrypted). Throws PDFImportError.locked / .writeFailed. Never writes to `url`.
    static func writeUnlockedCopy(of url: URL, password: String, to destination: URL) throws
}
enum PDFImportError: Error, Equatable { case locked, writeFailed }

enum CoverRenderer {
    static let maxPixelSize = 600
    /// Renders the page (crop box) on opaque white, uninverted, scaled so the longest side is maxPixelSize px,
    /// with PDFPage.draw(with: .cropBox, to:) into a CGContext; writes PNG (ImageIO) to destination.
    static func renderPDFPage(fileAt url: URL, pageIndex: Int, to destination: URL) throws
    /// Any ImageIO-readable image → PNG at destination, longest side ≤ maxPixelSize (downscale only).
    static func convertImage(at source: URL, to destination: URL) throws
}
enum CoverError: Error, Equatable { case cannotOpen, pageOutOfRange, cannotEncode }

/// Applies cover changes (SPEC F-11, ADR-0016). All file paths through FileStore.
struct CoverService: Sendable {
    init(fileStore: FileStore, documents: DocumentRepository)
    /// PDF: render page 0 to coverURL, then updateCover(coverPath: relativePath, coverSource: .automatic).
    /// Markdown: delete cover.png if present, updateCover(coverPath: nil, coverSource: .automatic).
    func resetCover(documentId: String) async throws
    /// convertImage → cover.png, coverSource .custom. The source URL is user-selected; caller handles security scope.
    func setCustomCover(documentId: String, imageURL: URL) async throws
    /// PDF only: render pageIndex → cover.png, coverSource .page.
    func usePageAsCover(documentId: String, pageIndex: Int) async throws
}
```
- Rendering and conversion run synchronously in the caller's context; `CoverService` methods run them inside `Task.detached` (or are called from a background actor), never on the main actor.
- Never pass `PDFDocument`/`PDFPage` across actors; never call `write(to:)` on the stored original or the user's file (only `writeUnlockedCopy` writes, to a new destination).
- `CoverService` reads the document with `documents.fetch(id:)`, resolves the original with `fileStore.url(forRelativePath: document.storedPath)`, and writes to `fileStore.coverURL(documentId:)`. Write the PNG to a temporary file in the same folder and replace atomically (`FileManager.replaceItemAt`), so a failed render keeps the old cover.

## Tests
Fixtures: `PDFFixtureBuilder` (`withMetadata`, `plainMultiPage`, `encrypted`, `damaged`, `coloredRegion`), written with `PDFFixtureBuilder.writeTemporary`.
`PDFImportInspectorTests`:
- `readsMetadataAndPageCount`: `withMetadata(title: "Neural Networks", author: "Ada Lovelace")` → `.ok` with that title/author, pageCount 1, `isEncrypted == false`; `plainMultiPage(pageCount: 5)` → pageCount 5.
- `detectsDamaged`: `damaged()` → `.damaged`.
- `locksAndUnlocksEncrypted`: `encrypted(password: "secret")` → `.locked` with nil and with "wrong"; `.ok` with "secret" (`isEncrypted == true`).
- `writesUnlockedCopy`: copy opens with `PDFDocument(url:)`, `isLocked == false`, same page count, page 0 text contains "Encrypted fixture"; the source file's bytes are unchanged. Wrong password throws `.locked`.
`CoverTests`:
- `rendersFirstPage`: `coloredRegion()` (US Letter 612 × 792 pt) → PNG with height 600 px and width `Int((612.0 / 792.0 * 600).rounded())`; the pixel at the center of `PDFFixtureBuilder.coloredRect` (scaled) is red (R > 200, G < 60, B < 60) and a corner pixel is white.
- `convertsImage`: write a 1200 × 300 PNG (CGContext + ImageIO) → converted PNG is 600 × 150.
- `pageOutOfRangeThrows`: page 3 of a 1-page PDF throws `.pageOutOfRange`.
- `coverServiceAppliesChanges`: `AppEnvironment.inMemory()` (+ remove folder); insert a PDF document whose `original.pdf` is the `coloredRegion` fixture copied to `originalFileURL(documentId:fileType:)`; `resetCover` → cover.png exists, row has `coverPath == "\(id)/cover.png"`, `.automatic`; `setCustomCover` with a PNG → `.custom`; `usePageAsCover(pageIndex: 0)` → `.page`. For a Markdown document, `resetCover` leaves `coverPath == nil` and removes an existing cover.png.

## Acceptance criteria
1. Import can tell ok, locked and damaged PDFs apart and read title, author and page count. → tests `PDFImportInspectorTests/readsMetadataAndPageCount`, `detectsDamaged`, `locksAndUnlocksEncrypted`
2. An unlocked copy can be stored without touching the source. → test `PDFImportInspectorTests/writesUnlockedCopy`
3. Covers render uninverted at 600 px and images convert. → tests `CoverTests/rendersFirstPage`, `convertsImage`, `pageOutOfRangeThrows`
4. Cover changes update `cover.png` and the row's `coverPath`/`coverSource`. → test `CoverTests/coverServiceAppliesChanges`

## Out of scope
- The import flow (T41), UI (T47, T50), dark-mode inversion (T54).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
