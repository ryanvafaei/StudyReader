# T02: Core support: clock, logging, FileStore

- **Phase:** 0
- **Agent:** data-layer
- **Depends on:** T01
- **ADRs:** docs/decisions/0011-build-signing-and-test-hosting.md
- **Visual check needed:** no

## Goal
Add the injectable clock (`Now`), the logging helper, and `FileStore`, the only code allowed to build file paths (ARCHITECTURE §3, §13, §14). Add the test helpers `FixedNow` and `TestFileStore`. Part of epic E0.2; the database (T04) gets its file location from `FileStore`.

Read first: ARCHITECTURE §3 (last bullet), §13, §14.

## Files to touch
- `StudyReader/Core/Support/Now.swift` (new)
- `StudyReader/Core/Support/Logging.swift` (new)
- `StudyReader/Core/Files/FileStore.swift` (new)
- `StudyReaderTests/Support/FixedNow.swift` (new)
- `StudyReaderTests/Support/TestFileStore.swift` (new)
- `StudyReaderTests/CoreTests/NowTests.swift` (new)
- `StudyReaderTests/CoreTests/FileStoreTests.swift` (new)

## Interfaces to produce

```swift
// Now.swift
import Foundation
protocol Now: Sendable {
    func callAsFunction() -> Date
}
/// The only place in the app that calls `Date()`.
struct SystemNow: Now {
    init() {}
    func callAsFunction() -> Date { Date() }
}

// Logging.swift
import os
import Foundation
enum Log {
    static let subsystem: String = Bundle.main.bundleIdentifier ?? "com.ryanvafaei.StudyReader"
    static func logger(_ category: String) -> Logger { Logger(subsystem: subsystem, category: category) }
    static let app = logger("app")
    static let database = logger("database")
    static let files = logger("files")
}
// Never log highlight text, notes, file contents, tokens, or emails (ARCHITECTURE §14).

// FileStore.swift
import Foundation
enum FileStoreError: Error, Equatable, LocalizedError {
    case invalidDocumentId(String)
    var errorDescription: String? { get }   // "Invalid document identifier."
}

struct FileStore: Sendable, Equatable {
    /// .../Application Support/StudyReader
    let rootURL: URL
    init(rootURL: URL)

    /// FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
    ///   appropriateFor: nil, create: true).appending(path: "StudyReader", directoryHint: .isDirectory)
    static func applicationSupport() throws -> FileStore

    var databaseURL: URL { get }      // rootURL/StudyReader.sqlite
    var documentsURL: URL { get }     // rootURL/Documents/

    func documentFolderURL(documentId: String) -> URL                         // Documents/<id>/
    func originalFileURL(documentId: String, fileExtension: String) -> URL    // Documents/<id>/original.<ext>
    func coverURL(documentId: String) -> URL                                  // Documents/<id>/cover.png
    func imagesFolderURL(documentId: String) -> URL                           // Documents/<id>/images/
    func snapshotURL(documentId: String, highlightId: String) -> URL          // Documents/<id>/snapshots/<highlightId>.png

    /// Paths stored in the database (storedPath, coverPath, imagePath) are relative to `documentsURL`,
    /// e.g. "<id>/original.pdf".
    func url(forRelativePath relativePath: String) -> URL
    /// Inverse of `url(forRelativePath:)`; nil if `url` is not inside `documentsURL`.
    func relativePath(for url: URL) -> String?

    /// Creates rootURL and documentsURL if missing (withIntermediateDirectories: true).
    func createRootDirectories() throws
    /// Creates Documents/<id>/ and returns it. Throws `.invalidDocumentId` unless `UUID(uuidString: documentId) != nil`.
    @discardableResult func createDocumentFolder(documentId: String) throws -> URL
    /// Removes Documents/<id>/ recursively. No error if it doesn't exist.
    /// Throws `.invalidDocumentId` unless `UUID(uuidString: documentId) != nil` (guards against deleting Documents/ itself).
    func deleteDocumentFolder(documentId: String) throws
    /// Names of subfolders of Documents/ that parse as UUIDs, sorted. Empty if Documents/ doesn't exist.
    /// Used at launch to find folders of interrupted imports (ARCHITECTURE §13).
    func documentFolderIds() throws -> [String]
}
```
Notes:
- Use `URL.appending(path:directoryHint:)`; folders use `.isDirectory`, files `.notDirectory`.
- `relativePath(for:)`: compare `standardizedFileURL.path(percentEncoded: false)` of both URLs; the result has no leading `/`.
- Call `FileManager.default` inside methods; don't store it.
- No other code may build paths under the library root; later tasks add methods here.

```swift
// StudyReaderTests/Support/FixedNow.swift
import Foundation
import Synchronization
@testable import StudyReader
/// Test clock. Thread-safe via Mutex; no @unchecked Sendable.
final class FixedNow: Now {
    init(_ date: Date)
    func callAsFunction() -> Date
    func set(_ date: Date)
    func advance(by seconds: TimeInterval)
}

// StudyReaderTests/Support/TestFileStore.swift
enum TestFileStore {
    /// FileStore rooted at FileManager.default.temporaryDirectory/StudyReaderTests/<UUID>/StudyReader.
    /// Directories are NOT created; call createRootDirectories() when needed.
    static func make() -> FileStore
}
```
`FixedNow` must be `Sendable` (it conforms to `Now`): store the date in `Mutex<Date>` from the `Synchronization` module and mark the class `final`.

## Acceptance criteria
1. `FixedNow` returns the set date, and `advance(by:)` moves it. → test `NowTests/fixedNowSetAndAdvance`
2. `SystemNow` returns a date within 5 s of the test's own reference. → test `NowTests/systemNowIsCurrent` (this test may call `Date()`)
3. Paths follow ARCHITECTURE §13: `databaseURL.lastPathComponent == "StudyReader.sqlite"`, original file is `Documents/<id>/original.pdf`, cover `cover.png`, images folder `images`, snapshot `snapshots/<hid>.png`, all under `rootURL`. → test `FileStoreTests/pathsFollowLayout`
4. `relativePath(for: originalFileURL(...)) == "<id>/original.pdf"` and `url(forRelativePath:)` maps it back to the same path; a URL outside Documents returns nil. → test `FileStoreTests/relativePathRoundTrip`
5. `createRootDirectories()` creates root and Documents; calling it twice doesn't throw. → test `FileStoreTests/createRootDirectoriesIsIdempotent`
6. `deleteDocumentFolder` removes a folder with files inside; deleting a missing folder doesn't throw. → test `FileStoreTests/deleteDocumentFolderRemovesContents`
7. `deleteDocumentFolder` and `createDocumentFolder` throw `.invalidDocumentId` for `""`, `".."`, `"a/b"`, `"not-a-uuid"`, and Documents/ still exists afterwards. → test `FileStoreTests/rejectsInvalidDocumentIds`
8. `documentFolderIds()` returns only UUID-named folders (ignores a file and a folder named `tmp`), sorted; returns `[]` when Documents/ is missing. → test `FileStoreTests/documentFolderIdsListsUUIDFolders`

All FileStore tests use `TestFileStore.make()`; none may touch the real Application Support folder.

## Out of scope
- Hashing, Debounce, file copying for import (Phase 1).
- Launch-time orphan cleanup logic (Phase 1); only `documentFolderIds()` is added here.

## Review log
<!-- Main session appends one line per review: date, model used, verdict, short reason -->
- 2026-10-23, Sonnet (effort medium): APPROVED. Tests 13/13, spec met, delete guard holds. Minor: unreachable branch FileStore.swift:79; url(forRelativePath:) does no '..' sanitizing, callers must pass DB values only.
