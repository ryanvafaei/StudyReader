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
