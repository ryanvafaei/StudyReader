# T29: FileStore stores lowercase extensions and returns only resolvable relative paths

- **Phase:** 1 (backlog L4, `docs/bugs/phase-0-second-pass.md` L4)
- **Agent:** data-layer
- **Depends on:** none
- **ADRs:** docs/decisions/0016-import-pipeline-and-stored-files.md ("Stored original"), docs/decisions/0012-data-layer-conventions.md (IDs)
- **Visual check needed:** no

## Goal
Before the importer stores any `storedPath`: (1) a source file named `SLIDES.PDF` must import, so the stored extension comes from `FileType`, not from `URL.pathExtension`; (2) `relativePath(for:)` must never return a path that `url(forRelativePath:)` rejects, so no unresolvable `storedPath` can be written.

## Files to touch
- `StudyReader/Core/Files/FileStore.swift` (modify)
- `StudyReaderTests/CoreTests/FileStoreTests.swift` (modify: add tests)
- `docs/bugs/backlog.md` (modify: remove the L4 entry, add "fixed by T29" to the section intro)

## Interfaces to produce
Add to `FileStore.swift` (an extension of the existing `FileType` from `ModelEnums.swift`; don't edit `ModelEnums.swift`):
```swift
extension FileType {
    /// The extension of the stored copy: "pdf" or "md" (ADR-0016). Never derived from the source file name.
    var storedFileExtension: String { get }      // .pdf → "pdf", .markdown → "md"

    /// Classifies a source file extension, case-insensitively.
    /// "pdf" → .pdf; "md", "markdown" → .markdown; anything else (including "") → nil.
    init?(fileExtension: String)
}

extension FileStore {
    /// Documents/<id>/original.<fileType.storedFileExtension>. Importers call this one.
    func originalFileURL(documentId: String, fileType: FileType) throws -> URL
}
```
Change in `FileStore`:
- `relativePath(for url: URL) -> String?`: keep the current prefix logic, then return the candidate only if `url(forRelativePath: candidate) != nil`; otherwise nil. Update its doc comment: "Returns nil unless the result resolves with `url(forRelativePath:)` (first component is a canonical document ID, no `.`/`..`)."
- `originalFileURL(documentId:fileExtension:)` keeps its strict validation (uppercase still throws). Add to its doc comment: "Pass `FileType.storedFileExtension`, never a source file's `pathExtension`. Prefer `originalFileURL(documentId:fileType:)`."
- Add one line to the type's doc comment: "Stored originals always use `FileType.storedFileExtension` (lowercase)."

## Tests (`FileStoreTests`; every store uses `defer { TestFileStore.remove(store) }`)
- `fileTypeFromSourceExtension`: `FileType(fileExtension:)` returns `.pdf` for `"pdf"`, `"PDF"`, `"Pdf"`; `.markdown` for `"md"`, `"MD"`, `"markdown"`, `"Markdown"`; nil for `"txt"`, `""`, `"pdf "`, `"mdx"`.
- `uppercaseSourceExtensionMapsToStoredExtension`: `let type = try #require(FileType(fileExtension: URL(filePath: "/x/SLIDES.PDF").pathExtension))`; `try store.originalFileURL(documentId: Self.docId, fileType: type).lastPathComponent == "original.pdf"`; the same for `"/x/Notes.MARKDOWN"` → `"original.md"`. `FileType.pdf.storedFileExtension == "pdf"`, `FileType.markdown.storedFileExtension == "md"`.
- `relativePathRejectsNonCanonicalFirstComponent`: with `docs = store.documentsURL`:
  - `relativePath(for: docs.appending(path: "notes/x.pdf"))` is nil;
  - `relativePath(for: docs.appending(path: "\(Self.docId.lowercased())/original.pdf"))` is nil;
  - `relativePath(for: docs)` is nil;
  - `relativePath(for: docs.appending(path: "\(Self.docId)/original.pdf")) == "\(Self.docId)/original.pdf"`;
  - `relativePath(for: try store.snapshotURL(documentId: Self.docId, highlightId: Self.highlightId))` is non-nil, and `url(forRelativePath:)` of it is non-nil.
- `relativePathAlwaysResolves`: for each URL in the list above, if `relativePath(for:)` returns a value `r`, then `url(forRelativePath: r) != nil`.

Existing tests stay unchanged and must pass, including `rejectsInvalidFileExtensions` (`"PDF"` still throws from `originalFileURL(documentId:fileExtension:)`) and `relativePathRoundTrip`.

## Acceptance criteria
1. Source extensions are classified case-insensitively. → test `FileStoreTests/fileTypeFromSourceExtension`
2. A `.PDF` source maps to `original.pdf`. → test `FileStoreTests/uppercaseSourceExtensionMapsToStoredExtension`
3. `relativePath(for:)` returns nil for non-canonical first components. → test `FileStoreTests/relativePathRejectsNonCanonicalFirstComponent`
4. Every returned relative path resolves. → test `FileStoreTests/relativePathAlwaysResolves`
5. Existing FileStore tests pass unchanged; L4 is removed from `docs/bugs/backlog.md` with "fixed by T29".

## Out of scope
- The importer (T41) and Markdown image file names (T40).
- Loosening `originalFileURL(documentId:fileExtension:)` validation.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
