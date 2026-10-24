# T41: ImportService

- **Phase:** 1 (E1.1: F-02, F-03 import, F-11 defaults)
- **Agent:** data-layer
- **Model / effort:** sonnet, high (from the first call; treat as escalated: review with code-reviewer effort high; two rejections → ask the user)
- **Depends on:** T33, T34, T39, T40
- **ADRs:** docs/decisions/0016-import-pipeline-and-stored-files.md (read in full), docs/decisions/0012-data-layer-conventions.md (dedupe by lookup), ARCHITECTURE §3, §13
- **Reference:** `.references/reader-source/Reader/Import/PublicationImportService.swift` (file copy, hashing, error reporting; read only this file)
- **Visual check needed:** no

## Goal
Import dropped or picked files and folders (F-02): classify, confirm large files, hash, skip duplicates, unlock encrypted PDFs, copy into the container, create the row with defaults (F-11), copy Markdown images (F-03), render the PDF cover and queue extraction. Crash-safe per ADR-0016. Returns a report the UI shows.

## Files to touch
- `StudyReader/Features/Library/Import/ImportService.swift` (new)
- `StudyReader/Features/Library/Import/ImportReport.swift` (new)
- `StudyReaderTests/LibraryTests/ImportServiceTests.swift` (new)
- `StudyReaderTests/LibraryTests/MarkdownImportTests.swift` (new)

(`AppEnvironment` wiring happens in T44, together with `ExtractionService`.)

## Interfaces to produce
```swift
/// Questions the import asks the user. The UI (T48) implements it; tests use stubs.
protocol ImportInteraction: Sendable {
    /// Asked once per file larger than the threshold. true = import it.
    func confirmLargeFile(named name: String, byteCount: Int64) async -> Bool
    /// Asked once per locked PDF. nil = the user cancelled.
    func password(forFileNamed name: String) async -> String?
    /// Asked when a Markdown file's relative images can't be read (sandbox). The UI shows an NSOpenPanel for
    /// directories, preselected on `folder`, with the message "Allow access to this folder so StudyReader can copy
    /// the images." Returns the URL the user approved, or nil if cancelled (ADR-0016, user decision Q5).
    func requestFolderAccess(for folder: URL, markdownFileName: String) async -> URL?
}

/// Implemented by ExtractionService (T44).
protocol ExtractionQueue: Sendable {
    func enqueue(documentId: String) async
}

enum ImportFailureReason: Sendable, Equatable {
    case damaged             // PDF can't be opened, Markdown isn't UTF-8 or can't be read
    case wrongPassword
    case passwordCancelled
    case declinedLargeFile
    case copyFailed          // file system or database error while storing
}
struct ImportedDocument: Sendable, Equatable { var documentId: String; var title: String }
struct ImportFailure: Sendable, Equatable { var fileName: String; var reason: ImportFailureReason }

struct ImportReport: Sendable, Equatable {
    var imported: [ImportedDocument] = []
    var duplicates: [String] = []              // titles of the existing documents
    var unsupported: [String] = []             // file names (top-level items only)
    var failures: [ImportFailure] = []
    var unreadableImageCount: Int = 0
    var missingImageCount: Int = 0             // informational, not in the summary
    /// User text, lines joined with "\n", in this order (omit lines that don't apply):
    /// 1. "Imported \(imported.count)" + (unsupported.isEmpty ? "" : ", skipped \(unsupported.count) (unsupported type)")
    ///    — shown when imported or unsupported is non-empty.
    /// 2. one line per duplicate: "Already in library: \(title)"
    /// 3. one line per failure: damaged "Couldn't open \(name)"; wrongPassword "Wrong password for \(name)";
    ///    passwordCancelled "Skipped \(name) (password required)"; declinedLargeFile "Skipped \(name) (larger than 500 MB)";
    ///    copyFailed "Couldn't import \(name)"
    /// 4. unreadableImageCount > 0 (images still unreadable after the folder-access step):
    ///    "\(n) images couldn't be read and show as placeholders." (n == 1: "1 image couldn't be read and shows as a placeholder.")
    var summary: String { get }
}

actor ImportService {
    static let defaultLargeFileThreshold: Int64 = 500_000_000      // 500 MB, decimal
    static let maxFolderDepth = 3

    init(fileStore: FileStore,
         documents: DocumentRepository,
         categories: CategoryRepository,
         covers: CoverService,
         settings: SettingsStore,
         now: any Now,
         extractionQueue: any ExtractionQueue,
         largeFileThreshold: Int64 = ImportService.defaultLargeFileThreshold)

    /// Imports files and folders in the given order, one file at a time.
    func importItems(at urls: [URL], interaction: any ImportInteraction) async -> ImportReport
}
```

## Behaviour
Expansion of `urls`:
- A top-level file: supported if `FileType(fileExtension: url.pathExtension) != nil`, else its file name goes to `unsupported`.
- A top-level folder: walk it with `FileManager.enumerator(at:includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])`. Include supported files whose `enumerator.level` is 1…4 (files directly in the folder are level 1; up to 3 nested subfolders, `maxFolderDepth`). Call `skipDescendants()` on directories at level 4. Unsupported files inside folders are ignored silently (not counted). Sort the folder's files by path.
- Call `startAccessingSecurityScopedResource()` on each top-level URL before reading and `stop…` after its files are done (harmless for drops).

Per file, in this order (ADR-0016):
1. Size from `.fileSizeKey`; if > threshold, `await interaction.confirmLargeFile`; false → failure `.declinedLargeFile`.
2. `Hashing.sha256Hex(ofFileAt:)`; error → `.copyFailed`.
3. `documents.fetch(fileHash:)` non-nil → `duplicates.append(existing.title)`, next file.
4. PDF: `PDFImportInspector.inspect(fileAt:password: nil)`. `.damaged` → `.damaged`. `.locked` → `await interaction.password`; nil → `.passwordCancelled`; inspect again with it; `.locked` → `.wrongPassword` (asked only once). Markdown: read `String(contentsOf:encoding: .utf8)`; error → `.damaged`; `FrontMatterParser.split`.
5. `id = UUID().uuidString`. Category = `settings.defaultCategoryId` if `categories.fetch(id:)` finds it, else `BuiltinCategory.lectureSlides.id`.
6. `fileStore.createDocumentFolder(documentId: id)`; destination = `originalFileURL(documentId: id, fileType:)`. Encrypted (password was needed) → `PDFImportInspector.writeUnlockedCopy`; otherwise `FileManager.copyItem`. Markdown: `MarkdownImageCollector.copyImages(sources: imageSources(in: body), from: url.deletingLastPathComponent(), to: fileStore.imagesFolderURL(documentId: id))`. Then the folder-access step (below). Add the final `unreadable`/`missing` counts to the report.
7. Insert `LibraryDocument(id: id, title: MetadataDefaults.title(metadataTitle: pdfInfo.title or frontMatter.title, fileName: url.lastPathComponent), author: MetadataDefaults.author(metadataAuthor: pdfInfo.author or frontMatter.author), categoryId:, fileType:, fileHash:, originalFilename: url.lastPathComponent, originalBookmark: try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil), storedPath: fileStore.relativePath(for: destination)!, pageCount: PDF page count or nil, addedAt: now())`. A `DatabaseError` with `.SQLITE_CONSTRAINT_UNIQUE` on `fileHash` → treat as duplicate (fetch by hash for the title).
8. Any error in 6–7 → `try? fileStore.deleteDocumentFolder(documentId: id)` and failure `.copyFailed` (or duplicate, as above).
9. PDF: `try? await covers.resetCover(documentId: id)` (a cover failure is logged, not a failure).
10. `await extractionQueue.enqueue(documentId: id)`; append to `imported`.

Folder-access step (ADR-0016, user decision Q5), for Markdown files only:
- If the first `copyImages` result has `unreadable > 0`, let `folder = url.deletingLastPathComponent().standardizedFileURL`.
- Keep a per-batch dictionary `folderAccess: [URL: URL?]` (folder → approved URL, or nil when declined). If `folder` has no entry, `await interaction.requestFolderAccess(for: folder, markdownFileName: url.lastPathComponent)` and store the answer. Never ask twice for the same folder in one `importItems` call; a new call (batch) may ask again.
- Approved: call `approved.startAccessingSecurityScopedResource()` the first time it's used in the batch (remember it), then `copyImages` again with the same sources and the same source folder (already-copied images are skipped). Use the second result's counts. If the user chose a different folder that doesn't cover the images, they stay unreadable.
- Declined (nil): keep the first result; the images become placeholders.
- At the end of `importItems`, call `stopAccessingSecurityScopedResource()` on every approved URL that was started. Never create or store a bookmark for these folders.
- The prompt happens after the document folder was created (step 6); a failure later still deletes the folder (step 8).

Logging: `Log.files` with document IDs and counts only; never file names, titles or paths.

## Tests
Use `AppEnvironment.inMemory(now: FixedNow(TestData.referenceDate))` (+ `defer TestFileStore.remove(env.fileStore)`), a `CoverService(fileStore:documents:)` from it, `TestSettings.make()` (+ remove), and these stubs in the test file:
```swift
struct StubInteraction: ImportInteraction {
    var allowLarge = true
    var password: String? = nil
    /// Called by requestFolderAccess; returns the URL to approve or nil to cancel. Default: cancel.
    var folderAnswer: @Sendable (URL) -> URL? = { _ in nil }
    /* record every call (kind + argument) in an actor so tests can count them */
}
actor RecordingQueue: ExtractionQueue { private(set) var ids: [String] = []; func enqueue(documentId: String) { ids.append(documentId) } }
```
`ImportServiceTests`:
- `importsPDFAndMarkdown` (SPEC F-02 AC1): a `plainMultiPage` PDF and `MarkdownFixtures.url("front-matter")` copied to a temp folder → `imported.count == 2`; each `storedPath` resolves via `fileStore.url(forRelativePath:)` to an existing file whose SHA-256 equals the source's; PDF row has `pageCount 5`, `coverPath "\(id)/cover.png"` and the cover file exists; queue has both ids; categoryId is Lecture slides; `addedAt == referenceDate`.
- `deduplicatesByHash` (SPEC F-02 AC2): importing the same PDF twice (second time under another name, `copy.PDF`) → one document; second report `duplicates == [title]` and `summary` contains `"Already in library: "`.
- `reportsUnsupportedAndDamaged` (SPEC F-02 AC3): a `.txt`, a `.png`, and `damaged()` saved as `broken.pdf` → no rows, `unsupported == ["a.txt", "b.png"]`, failure `.damaged` for `broken.pdf`; `summary == "Imported 0, skipped 2 (unsupported type)\nCouldn't open broken.pdf"`; `documentFolderIds()` is empty.
- `uppercaseExtensionImports`: `SLIDES.PDF` imports with `storedPath` ending `original.pdf`.
- `encryptedPDFWithPassword`: `encrypted(password: "secret")`, interaction password "secret" → imported; the stored copy opens unlocked; `fileHash` equals the source file's hash. With password "nope" → `.wrongPassword` and the password was asked once; with nil → `.passwordCancelled`.
- `largeFileNeedsConfirmation`: threshold 10 bytes; `allowLarge: false` → `.declinedLargeFile`, no row, no folder; `allowLarge: true` → imported.
- `folderDepthAndOrdering`: folder tree `root/a.pdf`, `root/1/2/3/b.md`, `root/1/2/3/4/c.md`, `root/notes.txt`, `root/.hidden.pdf` → imports a.pdf and b.md only; `unsupported` is empty.
- `usesDefaultCategorySetting`: `settings.defaultCategoryId = BuiltinCategory.paper.id` → row has Paper; a deleted/unknown id → Lecture slides.
- `summaryFormats`: a hand-built `ImportReport` with each line kind produces exactly the lines in order.
- Each test ends with `FTSIntegrity.check`.

`MarkdownImportTests`:
- `copiesRelativeImages` (SPEC F-03 AC2): `MarkdownFixtures.makeFolderWithImages()` → imported; `fileStore.markdownImageURL(documentId:storedFileName: MarkdownImageNaming.storedFileName(forSource: "images/diagram.png")!)` exists; nothing for `missing.png` or the remote URL; `report.missingImageCount == 1`, `unreadableImageCount == 0`.
- `frontMatter` (SPEC F-03 AC3): `front-matter.md` → title "Gradient Descent Notes", author "Ada Lovelace". (Hiding front matter in the rendered view is checked in T43.)
The folder-access tests simulate the sandbox by making the image unreadable: after `makeFolderWithImages()`, set `images/diagram.png` to POSIX permissions `0o000` (always restore `0o644` in `defer` before removing the folder).
- `folderAccessApprovedCopiesImages` (SPEC F-03 AC4): `folderAnswer` restores `0o644` on the image and returns the folder it was given → `requestFolderAccess` was called once with `notes.md`'s parent folder (standardized) and `markdownFileName == "notes.md"`; the image exists at `markdownImageURL`; `unreadableImageCount == 0`; no line about images in `summary`.
- `folderAccessCancelledLeavesPlaceholders` (SPEC F-03 AC4): `folderAnswer` returns nil → imported; no image copied; `unreadableImageCount == 1`; `summary` ends with `"1 image couldn't be read and shows as a placeholder."`.
- `folderAccessAskedOncePerFolderPerBatch`: a second Markdown file (different content, same image reference) in the same folder, both in one `importItems` call with a cancelling stub → `requestFolderAccess` called once; a second `importItems` call with a third file from that folder asks again (one more call).
- `noPromptWhenImagesReadable`: normal permissions → `requestFolderAccess` never called.
- `noBookmarkStored`: after an approved import, the `document` row's `originalBookmark` is the original file's bookmark only (or nil); no other file or setting is written for the folder (check `SettingsStore` keys are unchanged in a `TestSettings` store).

## Acceptance criteria
1. PDF and Markdown import with files copied into the container. → test `ImportServiceTests/importsPDFAndMarkdown`
2. The same file twice keeps one document. → test `ImportServiceTests/deduplicatesByHash`
3. Unsupported and damaged files are reported, not imported. → test `ImportServiceTests/reportsUnsupportedAndDamaged`
4. Relative images are copied; front matter prefills metadata. → tests `MarkdownImportTests/copiesRelativeImages`, `MarkdownImportTests/frontMatter`. Unreadable images trigger one folder-access request per folder and batch; approval copies them, cancel leaves placeholders, no access is kept. → tests `MarkdownImportTests/folderAccess*`, `noPromptWhenImagesReadable`, `noBookmarkStored` (SPEC F-03 AC4)
5. Uppercase extensions, encrypted PDFs, large files, folder depth and the category setting behave as specified. → tests `uppercaseExtensionImports`, `encryptedPDFWithPassword`, `largeFileNeedsConfirmation`, `folderDepthAndOrdering`, `usesDefaultCategorySetting`
6. No failed import leaves a folder behind. → assertions in tests 3 and 5

## Out of scope
- Extraction itself (T44), the launch orphan sweep (T44), UI (T48), cover UI (T50).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
