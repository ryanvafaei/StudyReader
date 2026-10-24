# T20: FileStore validates every ID, extension and relative path

- **Phase:** 0 (fix from bug hunt `docs/bugs/phase-0.md` L1)
- **Agent:** data-layer
- **Depends on:** T14
- **ADRs:** docs/decisions/0012-data-layer-conventions.md (IDs bullet); ARCHITECTURE §13
- **Visual check needed:** no

## Goal
Only `createDocumentFolder` and `deleteDocumentFolder` validate input today. The other path builders accept `..`, so `url(forRelativePath: "../StudyReader.sqlite")` resolves to the library database. Lowercase UUIDs are also accepted: on case-insensitive APFS, a lowercase ID is the same folder as the uppercase one, while SQLite keys stay case-sensitive. Phase 1 deletes files by stored relative paths and sweeps orphan folders, so every path FileStore builds must stay inside `Documents/<canonical id>/`.

## Files to touch
- `StudyReader/Core/Files/FileStore.swift` (modify)
- `StudyReaderTests/CoreTests/FileStoreTests.swift` (modify: add `try` where builders now throw, add tests)

## Interfaces to produce
```swift
enum FileStoreError: Error, Equatable, LocalizedError {
    case invalidDocumentId(String)
    case invalidHighlightId(String)
    case invalidFileExtension(String)

    var errorDescription: String? {
        switch self {
        case .invalidDocumentId: "Invalid document identifier."
        case .invalidHighlightId: "Invalid highlight identifier."
        case .invalidFileExtension: "Invalid file extension."
        }
    }
}

struct FileStore {
    /// true when `UUID(uuidString: id)?.uuidString == id` (canonical uppercase form, as `UUID().uuidString` makes).
    static func isCanonicalId(_ id: String) -> Bool

    func documentFolderURL(documentId: String) throws -> URL                          // .invalidDocumentId
    func originalFileURL(documentId: String, fileExtension: String) throws -> URL     // + .invalidFileExtension
    func coverURL(documentId: String) throws -> URL
    func imagesFolderURL(documentId: String) throws -> URL
    func snapshotURL(documentId: String, highlightId: String) throws -> URL           // + .invalidHighlightId

    /// nil unless: relativePath is non-empty, doesn't start with "/", has no "." or ".." or empty component
    /// (split on "/", omittingEmptySubsequences: false; a trailing "/" makes an empty component, so it is rejected),
    /// its first component is a canonical document ID, and the standardized result starts with
    /// trimmedPath(documentsURL) + "/".
    func url(forRelativePath relativePath: String) -> URL?

    /// Only subfolders whose name passes isCanonicalId, sorted.
    func documentFolderIds() throws -> [String]
}
```
- File extension rule: 1–10 characters, each in `a`–`z` or `0`–`9` (ASCII only). Uppercase is rejected. Phase 1 import lowercases extensions before calling.
- `createDocumentFolder` and `deleteDocumentFolder` keep their signatures and use the same canonical check, so lowercase IDs now throw.
- `databaseURL`, `documentsURL`, `rootURL`, `relativePath(for:)`, `createRootDirectories()` and `applicationSupport()` are unchanged.
- The private `validate` helper becomes `isCanonicalId`-based. Add a small private helper for each error case.

Search `StudyReader/` for every caller of the changed builders and add `try`. At planning time, nothing in `StudyReader/` outside FileStore called them. List any callers you find in the report.

## Tests (`FileStoreTests`; all stores use `defer { TestFileStore.remove(store) }` from T14)
Update the existing tests:
- add `try` (and `throws` on the test) where the builders are used;
- `relativePathRoundTrip` unwraps `url(forRelativePath:)` with `#require`;
- `rejectsInvalidDocumentIds` adds `Self.docId.lowercased()` to `invalidIds`.

New tests:
- `rejectsEscapingPaths`: `url(forRelativePath:)` returns nil for each of:
  - `"../StudyReader.sqlite"`
  - `"A/../../../x"`
  - `"\(Self.docId)/../../StudyReader.sqlite"`
  - `"\(Self.docId)/./original.pdf"`
  - `"/etc/passwd"`
  - `""`
  - `"\(Self.docId)"` + `"/"`
  - `"\(Self.docId.lowercased())/original.pdf"`
  - `"not-a-uuid/original.pdf"`

  It returns a URL for `"\(Self.docId)/original.pdf"` and `"\(Self.docId)/snapshots/\(Self.highlightId).png"`.
- `rejectsNonCanonicalIds`: each of these throws `FileStoreError.invalidDocumentId(<input>)`:
  - `documentFolderURL(documentId: Self.docId.lowercased())`
  - `coverURL(documentId: "..")`
  - `imagesFolderURL(documentId: "")`
  - `createDocumentFolder(documentId: Self.docId.lowercased())`

  `snapshotURL(documentId: Self.docId, highlightId: "../../../../evil")` throws `.invalidHighlightId("../../../../evil")`, and `snapshotURL(documentId: Self.docId, highlightId: Self.highlightId.lowercased())` throws `.invalidHighlightId`.
- `rejectsInvalidFileExtensions`: `originalFileURL(documentId: Self.docId, fileExtension:)` throws `.invalidFileExtension(x)` for `""`, `"../x"`, `"PDF"`, `"p d f"`, `"abcdefghijk"` (11 chars) and `"pdf/"`. It succeeds for `"pdf"`, `"md"` and `"markdown"`.
- `documentFolderIdsSkipsNonCanonicalNames`: after `createRootDirectories()`, create `Self.docId` via `createDocumentFolder`. Then use `FileManager.default.createDirectory` directly to create `"00000000-0000-4000-8000-00000000000a"` (a lowercase, non-canonical UUID; it's a different ID, so case-insensitive APFS doesn't merge it with `Self.docId`). `documentFolderIds() == [Self.docId]`.
- `isCanonicalIdRules`:
  - true for `Self.docId` and `UUID().uuidString`;
  - false for `Self.docId.lowercased()`, a `"{…}"`-wrapped ID, `""`, and the ID with a trailing space.

## Acceptance criteria
1. Relative paths that escape `Documents/<id>/`, or don't start with a canonical ID, return nil. → test `FileStoreTests/rejectsEscapingPaths`
2. Every builder rejects non-canonical document and highlight IDs. → test `FileStoreTests/rejectsNonCanonicalIds`
3. File extensions are validated. → test `FileStoreTests/rejectsInvalidFileExtensions`
4. The orphan-sweep input lists only canonical folders. → test `FileStoreTests/documentFolderIdsSkipsNonCanonicalNames`
5. The canonical ID rule is as specified. → test `FileStoreTests/isCanonicalIdRules`
6. The existing behaviour holds. → tests `FileStoreTests/pathsFollowLayout`, `relativePathRoundTrip`, `createRootDirectoriesIsIdempotent`, `deleteDocumentFolderRemovesContents`, `rejectsInvalidDocumentIds`, `documentFolderIdsListsUUIDFolders`
7. The full suite passes with no new warnings.

## Out of scope
- Delete-by-relative-path APIs and the launch orphan sweep (Phase 1).
- Changing the IDs used by database-only tests (they never reach FileStore).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, Sonnet (effort medium): APPROVED. Tests 138/138, traversal defences verified by reading, spec interfaces match.
