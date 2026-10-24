---
name: swift-testing-and-filestore-notes
description: Reusable API pitfalls and file locations for the core support layer (Now, Log, FileStore, test helpers) in StudyReader
metadata:
  type: reference
---

- `Core/Support/Now.swift`, `Core/Support/Logging.swift`, `Core/Files/FileStore.swift` hold the clock, `Log` categories, and the only path builder. Test helpers live in `StudyReaderTests/Support/` (`FixedNow`, `TestFileStore.make()`).
- `FixedNow` stores `Mutex<Date>` (Synchronization module); no `@unchecked Sendable` needed.
- `FileStore` validates document ids with `UUID(uuidString:)` only on create/delete; path builders don't validate.
- `FileStore.relativePath(for:)` trims trailing slashes on both sides before the prefix check (directory URLs can carry them).
- `#expect(throws: FileStoreError.invalidDocumentId(id)) { ... }` compiles and works with the Swift Testing in use.
- Full suite on T02 was 13 tests in 4 suites; test output has noisy `com.apple.linkd` lines, filter them out with grep.
- T14: `TestFileStore.remove(_:)` deletes `<UUID>/` only for `StudyReaderTests` / `StudyReader-InMemory` parents under temp. Use it in a `defer` right after every `TestFileStore.make()` or `AppEnvironment.inMemory()`. `AppEnvironment.removeStaleInMemoryFolders(in:olderThan:)` runs inside `inMemory()` (folders older than 1 h).
- `scripts/test.sh` filters take the Swift struct name (`StudyReaderTests/AppEnvironmentTests`), not the `@Suite` display string. A display-name filter runs 0 tests and still reports success, so check the "run with N tests" line.
