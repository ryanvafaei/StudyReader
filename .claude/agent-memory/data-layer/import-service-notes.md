---
name: import-service-notes
description: T41 ImportService files, test seams (StubInteraction, RecordingQueue, ImportHarness) and behaviours the tests rely on
metadata:
  type: reference
---

- Files: `Features/Library/Import/{ImportService,ImportReport}.swift`; tests in `StudyReaderTests/LibraryTests/{ImportServiceTests,MarkdownImportTests}.swift`.
- Shared test support lives in `ImportServiceTests.swift` (internal, reused by MarkdownImportTests): `StubInteraction` (allowLarge, password, folderAnswer closure, `log: InteractionLog`), `RecordingQueue`, `ImportHarness.make(largeFileThreshold:)` (+ `cleanup()`, `checkFTS()`), `makeImportTemporaryFolder()`.
- Folder access: per-batch `[URL: URL?]` keyed by `standardizedFileURL` parent folder; use `updateValue` so a nil (cancelled) answer is stored. Access is stopped at the end of `importItems`; no bookmark for the folder.
- Folder imports sort files by path, so `root/1/2/3/b.md` is imported before `root/a.pdf`. Depth limit 3 uses `enumerator.level`; hidden files are skipped. Only top-level unsupported files are reported (folder contents are filtered silently).
- Unreadable-image tests: chmod 0o000 the image, restore 0o644 in `folderAnswer` (approval) and in `defer` before removing the folder.
- T41 (2026-10-24): 16 tests in 2 suites, full suite 252 tests passing.
