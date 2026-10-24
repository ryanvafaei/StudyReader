---
name: swift-testing-and-filestore-notes
description: Reusable API pitfalls and file locations for the core support layer (Now, Log, FileStore, test helpers) in StudyReader
metadata:
  type: reference
---

- `Core/Support/Now.swift`, `Core/Support/Logging.swift`, `Core/Files/FileStore.swift` hold the clock, `Log` categories, and the only path builder. Test helpers live in `StudyReaderTests/Support/` (`FixedNow`, `TestFileStore.make()`).
- `FixedNow` stores `Mutex<Date>` (Synchronization module); no `@unchecked Sendable` needed.
- T20: every FileStore builder validates via `FileStore.isCanonicalId` (`UUID(uuidString:)?.uuidString == id`), so builders now `throws` and callers need `try`. `url(forRelativePath:)` returns `URL?`. Lowercase IDs are rejected everywhere, so test fixtures must use canonical uppercase IDs (digit-only IDs are fine).
- Extension rule validates over `utf8` bytes (1–10, a–z/0–9), not Characters: Character ranges accept combining sequences like "a\u{301}".
- `FileStore.relativePath(for:)` trims trailing slashes on both sides before the prefix check (directory URLs can carry them).
- `#expect(throws: FileStoreError.invalidDocumentId(id)) { ... }` compiles and works with the Swift Testing in use.
- Full suite on T02 was 13 tests in 4 suites; test output has noisy `com.apple.linkd` lines, filter them out with grep.
- T14: `TestFileStore.remove(_:)` deletes `<UUID>/` only for `StudyReaderTests` / `StudyReader-InMemory` parents under temp. Use it in a `defer` right after every `TestFileStore.make()` or `AppEnvironment.inMemory()`. `AppEnvironment.removeStaleInMemoryFolders(in:olderThan:)` runs inside `inMemory()` (folders older than 1 h).
- T29: `FileType.storedFileExtension` and `FileType(fileExtension:)` live in `Core/Files/FileStore.swift` (extension on the enum in ModelEnums). Use `originalFileURL(documentId:fileType:)` in importers. `relativePath(for:)` now returns nil unless `url(forRelativePath:)` resolves the result.
- `scripts/test.sh` filters take the Swift struct name (`StudyReaderTests/AppEnvironmentTests`), not the `@Suite` display string. A display-name filter runs 0 tests and still reports success, so check the "run with N tests" line.
- T29 (2026-10-24): `scripts/test.sh` was mode 600 (not executable) so `./scripts/test.sh` failed with "permission denied" while `build.sh` ran. Don't chmod or call it via `bash`; report BLOCKED instead.
