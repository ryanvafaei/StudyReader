# T52e: Grid covers refresh after a cover change; landscape covers are fitted, not cropped

- **Phase:** 1 (T52 checkpoint fix; SPEC F-01 covers, F-11 cover actions)
- **Agent:** ui-builder
- **Depends on:** T52
- **ADRs:** docs/decisions/0016-import-pipeline-and-stored-files.md (covers in `Documents/<id>/cover.png`); README "No schema change in Phase 1"
- **Visual check needed:** no (covered by UI tests; the ui-tester also reviews the attached cover crops)

## Goal
Findings from `docs/checkpoints/T52-manual-2026-10-25.md`:
- **Step 14.** After Choose Image… or Reset Cover and Save, the sheet preview updates but the grid card keeps the old cover until the grid is rebuilt. `CoverService` overwrites `cover.png` in place, so `document.coverPath` doesn't change and `DocumentCoverView`'s `.task(id: document.coverPath)` never runs again.
- **Step 8.** The 16:9 "Membrane Transport" cover fills the 3:4 frame, sharp and cropped left and right, with no blurred band. In `DocumentCoverView` the `scaledToFill()` blurred layer makes the `ZStack` wider than the frame, so the `scaledToFit()` layer fits that wider box and covers the blur.

**No schema change.** The reload token is the cover file's modification date, read from disk; nothing is stored. If you find this can't work without a new column, stop and report BLOCKED (README: no `v3` in Phase 1).

## Files to touch
- `StudyReader/Features/Library/LibraryModel.swift` (modify)
- `StudyReader/Features/Library/DocumentCoverView.swift` (modify)
- `StudyReader/Features/Library/LibraryItemViews.swift` (modify `LibraryGridCard`)
- `StudyReader/Features/Library/LibraryView.swift` (modify: pass the version to the card)
- `StudyReaderTests/LibraryTests/LibraryModelTests.swift` (modify: one test)

## Interfaces to produce
```swift
// LibraryModel
/// Cover file modification date per document id, refreshed on every observed list change. Documents without a
/// cover file are absent.
private(set) var coverVersions: [String: Date] = [:]

/// Reads `.contentModificationDateKey` of each item's cover file (`fileStore.url(forRelativePath: coverPath)`).
/// Items with no `coverPath`, an unresolvable path or no file are skipped. Pure apart from reading file metadata.
nonisolated static func coverVersions(for items: [LibraryItem], fileStore: FileStore) -> [String: Date]

// DocumentCoverView
init(document: LibraryDocument, categoryName: String, fileStore: FileStore, coverVersion: Date? = nil)

// LibraryGridCard gains:  let coverVersion: Date?   (passed through to DocumentCoverView)
```

## What to do
1. `LibraryModel.observe()`: for each emission, set `coverVersions = Self.coverVersions(for: observed, fileStore: …)` first, then `items = observed`. (`CoverService` replaces the file before it updates the row, so the emission sees the new date.) Use the model's existing `FileStore` from the environment.
2. `DocumentCoverView`: key the load on both values, e.g. a private `struct CoverReloadKey: Hashable { let path: String?; let version: Date? }` and `.task(id: CoverReloadKey(path: document.coverPath, version: coverVersion))`. `MetadataSheet` keeps calling it without `coverVersion` (its `.id(model.coverVersion)` already reloads).
3. `LibraryView.grid`: pass `coverVersion: model.coverVersions[item.id]` to `LibraryGridCard`.
4. `DocumentCoverView` body: size both image layers to the 3:4 frame. Replace the `ZStack` inside the overlay with
   ```swift
   Color.clear
       .overlay {
           Image(nsImage: coverImage).resizable().scaledToFill()
               .blur(radius: 24)
               .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.35))
       }
       .clipped()
       .overlay {
           Image(nsImage: coverImage).resizable().scaledToFit()
       }
   ```
   A portrait cover still fills the frame (fit and fill are nearly the same for 3:4 images). Update the doc comment.

## Acceptance criteria
1. Unit test `LibraryModelTests/coverVersionsFollowTheCoverFile`: with `AppEnvironment.inMemory(now:)`, write a small PNG at `fileStore.coverURL(documentId:)`, set its modification date to date A with `FileManager.setAttributes`, build a `LibraryItem` whose `coverPath` is `fileStore.relativePath(for:)` of that URL → `coverVersions` gives A for that id; rewrite the file and set date B → gives B; an item with `coverPath == nil` is absent. Clean up with `TestFileStore.remove`.
2. UI test `StudyReaderUITests/MetadataSheetTests/testChooseImageAndResetCoverUpdateTheCardCover` (step 14) turns green, or skips only through its own `XCTSkip` when the open panel isn't reachable (then the ui-tester's Peekaboo pass checks step 14).
3. UI test `StudyReaderUITests/LibraryCoverTests/testLandscapeCoverIsFittedOverABlurredBackground` (step 8) turns green; `LibraryCoverTests/testAllCardsShareOneWidth` keeps passing.
4. `./scripts/build.sh` succeeds; `./scripts/test.sh StudyReaderTests/LibraryModelTests` passes.

The implementer doesn't run `./scripts/uitest.sh` (CLAUDE.md); ui-tester runs the named UI tests during review. If names have shifted, use the tests covering steps 14 and 8 in `MetadataSheetTests.swift` and `LibraryCoverTests.swift`.

## Out of scope
Selection fill vs Markdown placeholder tint (U4), `CoverService`, `DocumentRepository`, any migration.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-26, code-reviewer sonnet medium: APPROVED. Cover mtime map refreshes grid covers; landscape fit fixed at the ZStack-width root cause; LibraryCoverTests 3/3 and testChooseImageAndResetCoverUpdateTheCardCover pass on CI. Note: one stat per item per emission runs on the main actor (as the spec prescribes).
