# T52h: No Picker or reentrant-layout warnings in the console

- **Phase:** 1 (T52 checkpoint fix; SPEC F-11 metadata sheet, F-01 AC4 document tabs, ADR-0017)
- **Agent:** ui-builder
- **Depends on:** T52, T52b (T52b changes the tab-join timing in the same files; this task covers only what remains after it)
- **ADRs:** docs/decisions/0017-reader-windows-and-commands.md (native window tabs only), docs/decisions/0019-ui-checks-xcuitest-and-peekaboo.md
- **Visual check needed:** yes. XCUITest can't read console output, so ui-tester checks the console on a Mac (`build/app.log`). In a cloud session this is NEEDS HUMAN under "Needs a Mac" in VISUAL_CHECKS.md. The picker part is also covered by a unit test.

## Goal
Step 39 of `docs/checkpoints/T52-manual-2026-10-25.md` logged three console warnings:
1. `Picker: the selection "" is invalid and does not have an associated tag`, many times. Source: `MetadataSheet`'s Category `Picker(selection: $model.categoryId)` with `.tag(category.id)` items. `MetadataEditorModel.categoryId` starts as `""` and `categories` as `[]` until `load()` finishes, so the sheet's first renders have a selection without a matching tag. (The other `Picker`s in the app use optional tags with a `nil` item, a fixed enum, or `SettingsView`'s `String?` selection, which never logs `""`.)
2. `-layoutSubtreeIfNeeded on a view which is already being laid out`, once, on the first reader open.
3. `NSHostingView is being laid out reentrantly`, when a reader tab opens.

Cause of 2 and 3: `WindowAccessorView.viewDidMoveToWindow` calls its callback synchronously, during SwiftUI's first layout of the reader window. In `ReaderWindowRoot` that callback changes window geometry and writes `@State`, so AppKit and SwiftUI lay out the hosting view again inside that layout pass. T52b already moves `addTabbedWindow`, the post-join `setFrame(…, display: true)` and `makeKeyAndOrderFront` to the next main-actor turn. It keeps two things synchronous: `window.setFrame(groupFrame, display: false)` in `joinMainTabGroup`, and `window = hostWindow` (a `@State` write) in `ReaderWindowRoot`. This task makes both run on the next turn. After that, the callback does only property sets and frame reads synchronously.

## Files to touch
- `StudyReader/Features/Library/Metadata/MetadataEditorModel.swift` (modify: one computed property)
- `StudyReader/Features/Library/Metadata/MetadataSheet.swift` (modify: the Category row only)
- `StudyReader/App/ReaderTabbing.swift` (modify: `joinMainTabGroup` and the `WindowAccessor` doc comment)
- `StudyReader/Features/Reader/ReaderWindowView.swift` (modify `ReaderWindowRoot` only)
- `StudyReaderTests/LibraryTests/MetadataEditorModelTests.swift` (modify: one test)
- `StudyReaderTests/AppTests/ReaderTabbingTests.swift` (modify: one test)

## Interfaces to produce
```swift
// MetadataEditorModel
/// true when `categoryId` is one of `categories`, so the Category picker has a tag for its selection.
/// false before `load()` finishes, and after a failed load.
var hasValidCategorySelection: Bool
```

## What to do
1. `MetadataEditorModel`: add `hasValidCategorySelection` (`categories.contains { $0.id == categoryId }`). Change nothing else in the model; `categoryId` stays a non-optional `String`.
2. `MetadataSheet`: show the Category `Picker` only when `model.hasValidCategorySelection`. Otherwise show `LabeledContent("Category") { Text("") }` in its place, so the form doesn't change height. Leave the picker's items, label and `.accessibilityLabel(Text("Category"))` as they are. Don't add a `nil`/empty item to the picker. Don't change the other fields or the tags/loading behaviour (backlog U2).
3. `ReaderTabbing.joinMainTabGroup(_:)`: start from T52b's version. The synchronous part keeps only `configure(window)`, the anchor lookup and `let groupFrame = anchor.frame`. Move `window.setFrame(groupFrame, display: false)` to the start of the deferred `Task { @MainActor in … }` block, before the `addTabbedWindow` step. The rest of the block stays as T52b left it: add to the group if it isn't there yet; `setFrame(groupFrame, display: true)` if the frame differs; `makeKeyAndOrderFront(nil)`. Update the doc comment: "Only property sets run synchronously; frame, tab and ordering changes run on the next main-actor turn, outside SwiftUI's layout pass." If T52b's code differs from this description, apply the same rule: nothing but property sets and frame reads may run synchronously.
4. `WindowAccessor` doc comment: add "The callback runs during SwiftUI's layout of the window. Do only property sets there; defer frame, tab, ordering and `@State` changes to the next main-actor turn." Don't change `WindowAccessorView`'s behaviour. `RootView`'s `configureMain` only sets properties and stays synchronous.
5. `ReaderWindowRoot`: in the `WindowAccessor` callback, replace the synchronous `window = hostWindow` with `Task { @MainActor in window = hostWindow }`. Keep T52b's `discardEmptyWindow` / `joinMainTabGroup` branch as it is.

## Acceptance criteria
1. Unit test `MetadataEditorModelTests/categoryPickerWaitsForValidSelection`: insert a document (`TestData.document(id:title:author:)` as in `loadAndSave`). Make the model; `hasValidCategorySelection` is false. `await load()`; it is true. Set `model.categoryId = "missing"`; it is false. Then a second model for an id that doesn't exist: after `load()`, `errorMessage != nil` and `hasValidCategorySelection` is false.
2. Unit test `ReaderTabbingTests/joinChangesNoFrameSynchronously`: an `NSWindow` with a 200 × 200 content rect (as in the existing tests). Record `window.frame`, call `ReaderTabbing.joinMainTabGroup(window)`; right after the call (no `await` in between), `window.frame` is unchanged and `tabbingIdentifier == "StudyReaderMain"`. Existing `configureSetsPreferredTabbing` and `joinConfiguresEvenWithoutGroup` keep passing.
3. `./scripts/test.sh StudyReaderTests/MetadataEditorModelTests StudyReaderTests/ReaderTabbingTests` passes; `./scripts/build.sh` succeeds.
4. UI tests keep passing (ui-tester runs them during review): `MetadataSheetTests` (the Category popup `popUpButtons["Category"]` still appears within 5 s), `CategoryManagerTests/testCreateRenameAssignAndDeleteACategory` (picks a category in the sheet), `LibraryOpenTests/testOpeningAReaderTabKeepsTheWindowSize` (T52b F1), `testDoubleClickOpensReaderAsTabInLibraryWindow`, `testReopeningAnOpenDocumentSelectsItsTab`, `testTabMovesToItsOwnWindowAndMergesBack`.
5. Visual check (ui-tester on a Mac, `./scripts/run-app.sh`): seed the library, open Edit Metadata (⇧⌘M) on a document and close it, then open two documents as reader tabs and close one. `build/app.log` (AppKit and SwiftUI messages are mirrored there) contains none of: `Picker: the selection`, `-layoutSubtreeIfNeeded on a view which is already being laid out`, `NSHostingView is being laid out reentrantly`. The tabs still open in the library window at its size, with no visible flash of a separate window. In a cloud session, mark this NEEDS HUMAN and list it under "Needs a Mac" in VISUAL_CHECKS.md with these steps.

The implementer doesn't run `./scripts/uitest.sh` or `./scripts/run-app.sh` (CLAUDE.md). If a layout warning is still logged after this change, ui-tester reports which action triggers it. The architect then plans a follow-up; this task doesn't widen.

## Out of scope
The metadata sheet's loading state (U2), `SettingsView`'s picker, the library filter pickers, `WindowAccessorView`'s timing, tab restore after quit, a custom tab bar, any change to `ReaderRouter` or `ReaderModel`.

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
