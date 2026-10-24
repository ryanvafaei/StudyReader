# T14: Remove temporary libraries created by tests and the test host

- **Phase:** 0 (fix from bug hunt `docs/bugs/phase-0.md` L7)
- **Agent:** data-layer
- **Depends on:** T13
- **ADRs:** docs/decisions/0011-build-signing-and-test-hosting.md (amended M4/L7 bullet)
- **Visual check needed:** no

## Goal
Each full test run leaves 3 `tmp/StudyReader-InMemory/<UUID>/` and 6 `tmp/StudyReaderTests/<UUID>/` folders, some with open SQLite files. Add one safe removal helper for tests, use it everywhere a test creates a FileStore or in-memory environment, and have `AppEnvironment.inMemory()` remove in-memory folders older than one hour. Later tasks (T15–T23) use the same helper.

## Files to touch
- `StudyReaderTests/Support/TestFileStore.swift` (modify: add `remove(_:)`)
- `StudyReader/App/AppEnvironment.swift` (modify: `inMemoryParentURL`, `removeStaleInMemoryFolders`, call it from `inMemory`)
- `StudyReaderTests/AppTests/AppEnvironmentTests.swift` (modify: use the helper, add two tests)
- `StudyReaderTests/AppTests/RootModelTests.swift` (modify)
- `StudyReaderTests/AppTests/AppLaunchModelTests.swift` (modify `startBecomesReady` only)
- `StudyReaderTests/CoreTests/DatabaseMigrationTests.swift` (modify `reopeningDoesNotRemigrate`, `onDiskDatabaseUsesWAL`)
- `StudyReaderTests/CoreTests/FileStoreTests.swift` (modify every test that calls `TestFileStore.make()`)

## Interfaces to produce
```swift
// TestFileStore (tests)
/// Removes the per-test folder `<parent>/<UUID>/` above `store.rootURL` (`<parent>/<UUID>/StudyReader`).
/// Does nothing unless rootURL.lastPathComponent == "StudyReader", the grandparent folder's name is
/// "StudyReaderTests" or "StudyReader-InMemory", and the standardized path starts with the standardized
/// FileManager.default.temporaryDirectory path. Errors are ignored (try?).
static func remove(_ store: FileStore)

// AppEnvironment (app)
/// FileManager.default.temporaryDirectory/StudyReader-InMemory
static var inMemoryParentURL: URL { get }

/// Removes direct subfolders of `parent` whose creation date (URLResourceKey.creationDateKey) is earlier than `cutoff`.
/// Missing `parent` is not an error. Each removal failure is ignored. Returns the number of folders removed.
@discardableResult
static func removeStaleInMemoryFolders(in parent: URL, olderThan cutoff: Date) -> Int
```
`inMemory(now:)` calls `removeStaleInMemoryFolders(in: inMemoryParentURL, olderThan: now().addingTimeInterval(-3600))` before it creates its own folder. Its own folder layout is unchanged (`inMemoryParentURL/<UUID>/StudyReader`). If it removes at least one folder, log it once with `Log.files.info("Removed \(count, privacy: .public) stale in-memory libraries")`. Log no paths.

Why one hour and not "everything": Swift Testing runs tests in parallel in one process, so another test's live folder may sit next to yours. Never delete folders younger than the cutoff.

## Test changes
Pattern for every test that makes a store or environment. Put the `defer` right after creation:
```swift
let store = TestFileStore.make()
defer { TestFileStore.remove(store) }
```
```swift
let environment = try AppEnvironment.inMemory()
defer { TestFileStore.remove(environment.fileStore) }
```
- `RootModelTests/defaultsToLibrary`: create the environment first with the pattern above, then `RootModel(environment: environment)`.
- `AppLaunchModelTests/startBecomesReady`: after the `guard case .ready(let environment) = model.state`, add `TestFileStore.remove(environment.fileStore)`. Don't change `startReportsFailureOnce`. T23 rewrites this file to async later; keep it synchronous now.
- `AppEnvironmentTests`: delete the private `removeParent(of:)` and use `TestFileStore.remove` instead.
- `DatabaseMigrationTests`, `FileStoreTests`: add the `defer` to each test that calls `TestFileStore.make()`.

New tests in `AppEnvironmentTests`:
- `removeStaleInMemoryFoldersKeepsRecentOnes`: make a parent `temporaryDirectory/StudyReaderTests/<UUID>/parent` (remove `<UUID>` in a `defer`). Create subfolders `old` and `new`. Set `old`'s creation date to `Date(timeIntervalSince1970: 1_700_000_000)` with `FileManager.default.setAttributes([.creationDate: …], ofItemAtPath:)`. Call `removeStaleInMemoryFolders(in: parent, olderThan: Date(timeIntervalSince1970: 1_750_000_000))`. Expect a return value of 1, `old` gone, `new` present. Then call it on a missing folder: it returns 0 and doesn't throw.
- `testFileStoreRemoveOnlyDeletesTestFolders`: (a) `let store = TestFileStore.make(); try store.createRootDirectories()`, then `TestFileStore.remove(store)`: `store.rootURL.deletingLastPathComponent()` no longer exists. (b) `let foreign = FileStore(rootURL: temporaryDirectory/StudyReaderTests/<UUID>/Other)` with that folder created: `remove(foreign)` leaves it in place, because the last component isn't "StudyReader". Remove it yourself in a `defer`.

## Acceptance criteria
1. Old in-memory folders are removed, recent ones are kept. → test `AppEnvironmentTests/removeStaleInMemoryFoldersKeepsRecentOnes`
2. The removal helper deletes only test-created folders. → test `AppEnvironmentTests/testFileStoreRemoveOnlyDeletesTestFolders`
3. Every test that calls `TestFileStore.make()` or `AppEnvironment.inMemory()` removes what it created. → reviewer greps both calls in `StudyReaderTests/` and finds a matching `TestFileStore.remove` in each test.
4. Existing tests still pass: `AppEnvironmentTests`, `RootModelTests`, `AppLaunchModelTests`, `DatabaseMigrationTests`, `FileStoreTests`.
5. The full suite passes with no new warnings.

## Out of scope
- Cleaning the folders that already exist in the user's container `tmp` (the next run older than one hour removes the in-memory ones; the user may delete `tmp/StudyReaderTests/` by hand).
- `PDFFixtureBuilder.writeTemporary` and `MarkdownFixtures.makeFolderWithImages` (their tests already clean up).
- Test-host detection (T15), the async launch (T23), FileStore validation (T20).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-24, Sonnet (effort medium): APPROVED. Tests 97/97, all 5 criteria met; minor non-blocking nits only.
