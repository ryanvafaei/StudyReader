# T52c: Reader title for a missing original; subtitle follows category changes

- **Phase:** 1 (T52 checkpoint fix; SPEC F-01 tabs show title and category, ADR-0017)
- **Agent:** ui-builder
- **Depends on:** T52
- **ADRs:** docs/decisions/0017-reader-windows-and-commands.md
- **Visual check needed:** no (covered by UI tests)

## Goal
Findings from `docs/checkpoints/T52-manual-2026-10-25.md`:
- Step 30: when the original file is missing, the reader shows "The document file is missing." but the tab and window title are blank. `ReaderModel.load()` sets `document` only after the file check passes.
- Step 26 (found with step 24): after the document's category was renamed or deleted, the open tab kept the old category as its subtitle. `categoryName` is read once in `load()`.

## Files to touch
- `StudyReader/Features/Reader/ReaderModel.swift` (modify)
- `StudyReader/Features/Reader/ReaderWindowView.swift` (modify `ReaderTabContent`: one `.task`)
- `StudyReaderTests/ReaderTests/ReaderModelTests.swift` (modify: two tests)

## Interfaces to produce
```swift
// ReaderModel
/// Keeps `document` (title, author, categoryId) and `categoryName` in step with metadata edits, category renames
/// and category deletions (a deleted category's documents move to Other). Observes
/// `documentRepository.observeItems()` and uses the item whose id is `documentId`. Runs until the calling task is
/// cancelled. Errors are logged (Log.database) and end the observation; they don't change `state`.
func observeMetadata() async

/// Applies one observed item. Updates `categoryName` when it differs. Updates `document` only when title, author
/// or categoryId differ (copy, change those three fields, assign), so position and progress saves don't
/// re-render the tab. Does nothing to `document` while it is nil.
func applyMetadata(_ item: LibraryItem)
```

## What to do
1. In `load()`, assign `document = loaded` and fetch `categoryName` right after the fetch succeeds, before the file-existence check. `fileURL` stays nil and `state` becomes `.failed("The document file is missing.")` as today.
2. Add `observeMetadata()` and `applyMetadata(_:)` as above.
3. `ReaderTabContent`: add `.task { await model.observeMetadata() }` next to the existing `.task`s. `.navigationTitle` / `.navigationSubtitle` stay as they are.

## Acceptance criteria
1. A missing original keeps the title → unit test `ReaderModelTests/missingFileKeepsDocumentTitle`: insert with `ReaderTestSupport.insertDocument(session, id:, withFile: false)`, `load()`, expect `state == .failed("The document file is missing.")`, `fileURL == nil`, `document?.title` equal to the inserted title and `categoryName` non-nil. The existing `missingFileFails` keeps passing.
2. The subtitle follows renames and deletions → unit test `ReaderModelTests/subtitleFollowsCategoryRenameAndDelete`: create a custom category (`categoryRepository.create(name:)`), move the document into it (`documentRepository.updateMetadata`), `load()`, run `observeMetadata()` in a `Task`; `categoryRepository.rename(id:to:)` → poll (bounded, ≤ 2 s) until `categoryName` is the new name; `categoryRepository.delete(id:)` → poll until `categoryName == "Other"`; cancel the task. `.timeLimit(.minutes(1))`.
3. UI tests turn green: `StudyReaderUITests/ReaderChromeTests/testMissingOriginalShowsErrorAndKeepsTheTitle` (step 30) and `ReaderChromeTests/testOpenReaderSubtitleFollowsACategoryDeletion` (step 26/24); `testTitleAndSubtitleShowDocumentAndCategory` (step 26) keeps passing.
4. `./scripts/build.sh` succeeds; `./scripts/test.sh StudyReaderTests/ReaderModelTests` passes.

The implementer doesn't run `./scripts/uitest.sh` (CLAUDE.md); ui-tester runs the named UI tests during review. If names have shifted, use the tests in `ReaderChromeTests.swift` covering steps 30 and 24/26.

## Out of scope
Hiding the colour menu and inspector toggle for a missing original (U7), any repository change (use `observeItems()` as it is), engine code.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-26, code-reviewer sonnet medium: APPROVED. Missing-file keeps the title; subtitle follows category rename/delete via observeMetadata; both target UI tests and ReaderModel unit tests pass on CI.
