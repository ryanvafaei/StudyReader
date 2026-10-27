# T52j: Metadata sheet loading and title error, quiet successful imports, Settings colour labels

- **Phase:** 1 (T52 checkpoint fix; SPEC F-11 metadata sheet, F-02 import feedback, F-06/F-22 colour labels in Settings)
- **Agent:** ui-builder
- **Depends on:** T52, T52h (Category picker placeholder), T52i (adds a test to `MetadataSheetTests.swift` first)
- **ADRs:** docs/decisions/0015-settings-and-injected-sleep.md, docs/decisions/0019-ui-checks-xcuitest-and-peekaboo.md
- **Visual check needed:** yes, Mac only (sheet without a flash of empty content, light/dark Settings rows). Everything else is covered by the tests below.

## Goal
Items from `docs/checkpoints/T52-manual-2026-10-25.md` (U2, U5, U6) and `docs/checkpoints/T52-cloud-2026-10-27.md` (S1), approved by the user on 2026-10-27. Four independent parts; do them in order A–D and keep each part's changes to its files.
- **A, U2**: the metadata sheet briefly shows empty Title/Author fields and "No tags yet" before its data loads.
- **B, S1**: the blank-title error shows at the bottom of the sheet, far from the Title field.
- **C, U5**: a successful import shows a modal "Import finished / Imported 1" alert.
- **D, U6**: Settings > General > Highlight colors: every row's left text reads "Label" instead of the colour's name, and the list is cut off at the bottom of the window.

This task is larger than usual (four parts). If a part can't be finished, report which parts are done; don't widen any part.

## Files to touch
- A: `StudyReader/Features/Library/Metadata/MetadataEditorModel.swift`, `StudyReader/Features/Library/Metadata/MetadataSheet.swift`, `StudyReader/Features/Annotations/Tags/TagFieldModel.swift`, `StudyReader/Features/Annotations/Tags/TagFieldView.swift` (modify)
- B: `MetadataEditorModel.swift`, `MetadataSheet.swift` (same files)
- C: `StudyReader/Features/Library/Import/ImportReport.swift`, `StudyReader/Features/Library/Import/ImportCoordinator.swift` (modify)
- D: `StudyReader/Features/Settings/SettingsView.swift`, `StudyReader/Features/Annotations/HighlightPalette.swift` (modify)
- Unit tests (modify): `StudyReaderTests/LibraryTests/MetadataEditorModelTests.swift`, `StudyReaderTests/AnnotationsTests/TagFieldModelTests.swift`, `StudyReaderTests/LibraryTests/ImportCoordinatorTests.swift`, `StudyReaderTests/AppTests/HighlightPaletteTests.swift`
- UI tests: `StudyReaderUITests/MetadataSheetTests.swift`, `StudyReaderUITests/ExternalOpenTests.swift`, `StudyReaderUITests/Support/StudyReaderUI.swift` (doc comment of one helper only) (modify); `StudyReaderUITests/SettingsTests.swift` (new)

## Interfaces to produce
```swift
// MetadataEditorModel
/// false until the first `load()` has finished (successfully or not). The sheet hides its fields until then.
private(set) var hasLoaded: Bool
/// Message for the Title field, shown directly below it. Set when Save is refused for a blank title; cleared when
/// `title` changes. `errorMessage` stays for every other failure (load, save, cover).
private(set) var titleError: String?

// TagFieldModel
/// false until the target's assigned tags have been observed once (or that observation failed).
/// The view shows "No tags yet" only after that.
private(set) var hasLoadedAssignedTags: Bool

// ImportReport
/// true when the user should read the summary: nothing was imported, or there is a duplicate, an unsupported file,
/// a failure, or an unreadable image. A batch that only imported documents needs no attention.
var needsAttention: Bool

// ImportCoordinator
typealias Announcer = @MainActor (_ text: String) -> Void
init(importService: ImportService,
     folderPanel: @escaping FolderPanel = ImportCoordinator.showFolderAccessPanel,
     announce: @escaping Announcer = ImportCoordinator.postAnnouncement)
/// VoiceOver announcement (NSAccessibility .announcementRequested, high priority) on NSApp; does nothing without NSApp.
static func postAnnouncement(_ text: String)

// HighlightPalette
/// Capitalized colour name for row labels: "Yellow", "Green", "Blue", "Pink", "Purple" (SPEC F-06).
/// `name(_:)` stays lowercase for use inside sentences.
static func title(_ color: HighlightColor) -> String
```

## What to do

### A. Metadata sheet loading state (U2)
1. `MetadataEditorModel.load()`: set `hasLoaded = true` at the end of every path (success, missing document, thrown error). Use `defer { hasLoaded = true }` at the top of the method.
2. `TagFieldModel.observeAssigned()`: set `hasLoadedAssignedTags = true` after assigning `tags` on each emission (setting it again is harmless), and in the `catch` before returning (also when cancelled is fine).
3. `TagFieldView`: show "No tags yet" only when `model.hasLoadedAssignedTags && model.tags.isEmpty`. Before that, show `Text(" ")` with the same `.font(.callout)` and `.accessibilityHidden(true)`, so the height doesn't change. Chips and the field are unchanged. This also helps the other hosts (T62, T69).
4. `MetadataSheet`: `private var isReady: Bool { model.hasLoaded && tagModel.hasLoadedAssignedTags }`. Group everything between the "Edit Metadata" title and the buttons row (cover row, `Form`, tags block, the general error text) in one `VStack(alignment: .leading, spacing: 16)` and apply to it:
   ```swift
   .opacity(isReady ? 1 : 0)
   .accessibilityHidden(!isReady)
   .overlay {
       if !isReady {
           ProgressView()
               .controlSize(.small)
               .accessibilityLabel("Loading")
       }
   }
   ```
   The content stays laid out while hidden, so the sheet has its final size from the first frame and nothing jumps. The `.task { await model.load() }` and `TagFieldView`'s own `.task` keep running (the views exist, only invisible). Save gets `.disabled(!isReady)`; Cancel stays enabled. Keep T52h's Category branch exactly as it is (`hasValidCategorySelection` → `Picker`, else the `LabeledContent` placeholder); after a failed load it still shows the placeholder.

### B. Blank-title error next to the Title field (S1)
5. `MetadataEditorModel`: add `titleError`. `title` gets `didSet { if title != oldValue { titleError = nil } }`. In `save()`, the `DocumentEditError.emptyTitle` branch sets `titleError = Self.message(for: DocumentEditError.emptyTitle)` and leaves `errorMessage` unchanged (nil); a successful save clears both. Nothing else changes.
6. `MetadataSheet`, inside the `Form` directly after the Title `TextField`:
   ```swift
   if let titleError = model.titleError {
       Text(titleError)
           .font(.callout)
           .foregroundStyle(.red)
           .accessibilityLabel(Text(titleError))
   }
   ```
   The bottom error text keeps showing `model.errorMessage` only.

### C. No alert for a successful import (U5)
SPEC F-02 asks for messages only for problems: "Already in library: <title>" (step 1), the skipped-unsupported summary, the large-file confirmation, the password prompt and its error, "Couldn't open <name>". It asks for no success message; the new document showing in the library is the confirmation (F-02 AC1 "shows them in the library"), and the toolbar spinner plus the card's "Indexing…" badge show progress (SPEC §4 Performance, "progress in the library item"). Decision: no modal alert and no new visual indicator for a batch that needs no attention; VoiceOver users get the summary as an announcement (SPEC §4 Accessibility). Alerts stay for every batch with a problem. (T48's visual check expected "Imported 2" to be shown; this supersedes it.)
7. `ImportReport.needsAttention`: `imported.isEmpty || !duplicates.isEmpty || !unsupported.isEmpty || !failures.isEmpty || unreadableImageCount > 0`. `missingImageCount` doesn't count (informational, as for `summary`).
8. `ImportCoordinator`: store `announce`. In `finishBatch`, keep appending every summary to `summaryHistory`. Then: if `report.needsAttention`, `lastSummary = summary` (the alert shows, as today); else leave `lastSummary` as it is (nil unless an earlier alert is still open) and call `announce(summary)`. Update the doc comments of `lastSummary` ("Summary of the last import that needs the user's attention; the UI shows it in an alert and sets it to nil when dismissed. Batches that only imported documents don't set it.") and `summaryHistory` ("every summary, including quiet ones"). `ImportPromptViews.swift` needs no change.

### D. Settings colour labels (U6)
9. `HighlightPalette.title(_:)`: `String(localized: "Yellow")` etc.
10. `ColorLabelRow` body: the colour name is the row label, the editable text is the value:
    ```swift
    LabeledContent {
        TextField("Label", text: $draft)
            .labelsHidden()
            .focused($isFocused)
            .onSubmit { commit() }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .accessibilityLabel(String(localized: "Label for \(HighlightPalette.name(color)) highlights"))
    } label: {
        Label {
            Text(HighlightPalette.title(color))
        } icon: {
            Circle()
                .fill(HighlightPalette.color(color))
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
        }
    }
    .onAppear { draft = settings.label(for: color) }
    ```
    Keep `commit()` and the accessibility label exactly (the text field's label "Label for yellow highlights" etc. is what tests and VoiceOver use).
11. Cut-off list: `GeneralSettingsView`'s `Form` gets `.scrollDisabled(true)` and `.fixedSize(horizontal: false, vertical: true)` after `.formStyle(.grouped)`, so it takes its full content height and the Settings window grows to fit the tab. Don't set a fixed height. Leave the Reading and Data tabs unchanged.

## Tests

### Unit tests
- `MetadataEditorModelTests/hasLoadedAfterLoadEvenWhenTheDocumentIsMissing`: model for an inserted document: `hasLoaded == false` before `load()`, `true` after. A second model for a missing id: `true` after `load()`, with `errorMessage != nil`.
- `MetadataEditorModelTests/emptyTitleShowsError` (**update deliberately**, it asserted the old place of the message): after `title = "   "` and a refused save, `titleError == "A title is required."` and `errorMessage == nil`; the row keeps "Keep me". Replace the `dismissError()` step with: `model.title = "Fixed"` → `titleError == nil`; `await model.save()` is true; both messages nil. Keep the test name.
- `TagFieldModelTests/assignedTagsLoadedAfterFirstObservation`: document with one assigned tag (`findOrCreate` + `addTag(…toDocument…)` as in `documentTarget`); `hasLoadedAssignedTags == false` at init; start `observe()` in a `Task` (cancel in `defer`); `ReaderTestSupport.waitUntil { model.hasLoadedAssignedTags }` is true and `model.tags.count == 1` at that point. Second case: a document with no tags → after the wait, `hasLoadedAssignedTags` is true and `tags` is empty.
- `ImportCoordinatorTests/importsAndPublishesSummary` (**update deliberately**): after the import finishes (poll until `!isImporting && summaryHistory.count == 1`), `summaryHistory == ["Imported 1"]`, `lastSummary == nil`, and an injected recorder `announce` got exactly `["Imported 1"]`. Rename it to `quietImportShowsNoAlertAndAnnounces`. Use a small `@MainActor final class AnnouncementRecorder { private(set) var texts: [String] = []; func record(_ text: String) { texts.append(text) } }` in the test file and pass `announce: recorder.record`.
- `ImportCoordinatorTests/duplicateImportStillShowsTheSummary`: import the same PDF twice (two batches, recorder injected); after both finish, `lastSummary` starts with "Already in library:" and the recorder has only the first batch's "Imported 1".
- `ImportCoordinatorTests/reportNeedsAttentionOnlyForProblems`: `ImportReport` values: one imported → false; empty report → true; imported + one duplicate → true; imported + one unsupported → true; imported + one failure → true; imported + `unreadableImageCount = 1` → true; imported + `missingImageCount = 2` → false.
- Existing `ImportCoordinatorTests` that wait on `lastSummary` must still pass: `largeFileDecline` (a failure → alert, unchanged). `passwordRoundTrip` and `batchesRunInOrder` read `summaryHistory` (unchanged).
- `HighlightPaletteTests/titlesAreCapitalizedColourNames`: `HighlightColor.allCases.map(HighlightPalette.title)` == `["Yellow", "Green", "Blue", "Pink", "Purple"]` (in `allCases` order; check the enum's order and adjust the expected array to it).

### UI tests
- `MetadataSheetTests/testFieldsAppearWithTheirStoredValues` (new, U2): select `Sample.lecture`, `settle()`, ⇧⌘M. As soon as `sheet.textFields["Title"].waitForExistence(timeout: 5)` returns, without waiting further: Title value == `Sample.lecture`, Author value == "Dr. A. Rivera", `sheet.staticTexts["No tags yet"].exists == false`, and a chip button whose label begins with "Remove tag " exists (the lecture has tags). Cancel.
- `MetadataSheetTests/testBlankTitleShowsAnInlineErrorAndKeepsTheSheetOpen` (**tighten deliberately**, S1): after the error appears, also assert that it sits directly under the Title field: `error.frame.minY >= title.frame.maxY - 1`, `error.frame.minY - title.frame.maxY < 40`, and `error.frame.maxY <= sheet.textFields["Author"].frame.minY + 1`. Keep the screenshot.
- `ExternalOpenTests/testOpenWithWhileRunningImportsIntoTheRunningInstance` and `testOpenWithWhenNotRunningLaunchesOnceAndImports` (**update deliberately**, U5): remove the `dismissImportAlertIfShown(timeout: 10)` calls. After the imported card exists, assert no import alert is showing: `XCTAssertFalse(ui.alertButton("OK").exists, "A successful import showed an alert.")` (use `launched` in the cold-start test).
- `ExternalOpenTests/testDuplicateOpenWithStillShowsTheSummaryAlert` (new, U5): launch with the sample library, open a new PDF "Open With Duplicate" with `StudyReaderUI.openExternally` (as in the running-instance test, `activates = true`), wait for its card (15 s), assert no alert; open the same file URL again; then `ui.alertButton("OK").waitForExistence(timeout: 10)` is true and a static text containing "Already in library" exists (`app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Already in library' OR value CONTAINS 'Already in library'")).firstMatch`); click OK.
- `StudyReaderUI.dismissImportAlertIfShown` doc comment: "Dismisses the import summary alert if it's showing. Since T52j it appears only when an import needs attention (duplicates, skipped or failed files)." No code change. If nothing calls it any more, leave it in place for later tests.
- `SettingsTests.swift` (new class `SettingsTests`, `continueAfterFailure = true`), `testHighlightColorRowsShowColourNamesAndFitTheWindow` (U6): `StudyReaderUI.launch(seed: false)`; type ⌘, ; find the Settings window: `ui.app.windows.matching(NSPredicate(format: "identifier == 'com_apple_SwiftUI_Settings_window' OR title == 'General'")).firstMatch`, wait 5 s; click its toolbar button "General" if it exists. Then: static texts "Yellow", "Green", "Blue", "Pink", "Purple" exist in that window; no static text with label or value exactly "Label" exists in it; the text field "Label for purple highlights" exists and `window.frame.contains(field.frame)` is true. Attach a screenshot "Settings General". Close the window with ⌘W.

## Acceptance criteria
1. The sheet shows no empty fields and no "No tags yet" before its data → UI test `MetadataSheetTests/testFieldsAppearWithTheirStoredValues`; unit tests `MetadataEditorModelTests/hasLoadedAfterLoadEvenWhenTheDocumentIsMissing`, `TagFieldModelTests/assignedTagsLoadedAfterFirstObservation` (U2).
2. The blank-title error is directly under the Title field → UI test `MetadataSheetTests/testBlankTitleShowsAnInlineErrorAndKeepsTheSheetOpen` (tightened); unit test `MetadataEditorModelTests/emptyTitleShowsError` (updated) (S1).
3. A successful import shows no alert; problems still do → unit tests `ImportCoordinatorTests/quietImportShowsNoAlertAndAnnounces`, `duplicateImportStillShowsTheSummary`, `reportNeedsAttentionOnlyForProblems`; UI tests `ExternalOpenTests/testOpenWithWhileRunningImportsIntoTheRunningInstance`, `testOpenWithWhenNotRunningLaunchesOnceAndImports` (updated), `testDuplicateOpenWithStillShowsTheSummaryAlert` (new) (U5).
4. Settings rows show the colour names and the list fits → UI test `SettingsTests/testHighlightColorRowsShowColourNamesAndFitTheWindow`; unit test `HighlightPaletteTests/titlesAreCapitalizedColourNames` (U6).
5. These keep passing: all of `MetadataSheetTests`, `CategoryManagerTests/testCreateRenameAssignAndDeleteACategory` (uses the sheet's Category popup), `ReaderChromeTests/testShiftCommandMOpensTheMetadataSheetInTheReader`, `ReaderChromeTests/testHighlightColorMenuShowsColouredSwatchesAndKeepsTheChoice` (reads the colour labels), and the unit suites `MetadataEditorModelTests`, `TagFieldModelTests`, `ImportCoordinatorTests`, `ImportServiceTests`, `AppSettingsTests`, `SettingsStoreTests`.
6. Updated tests are exactly the ones listed above as "update deliberately" or "tighten deliberately"; no assertion is removed without the replacement named here → reviewer compares the diff with this list.
7. `./scripts/build.sh` succeeds; `./scripts/test.sh` passes.
8. Visual check (Mac; in a cloud session under "Needs a Mac" in VISUAL_CHECKS.md): seed the library, open Edit Metadata (⇧⌘M) on several documents: no flash of empty fields, "No tags yet" or an empty Category row, and the sheet doesn't change size; blank the title and Save: the red message sits under Title. Import one PDF by drag: no alert, the card appears; drag the same PDF again: the "Already in library" alert appears. Settings > General in light and dark: five rows with swatch and colour name on the left, editable label on the right, nothing cut off.

The implementer doesn't run `./scripts/uitest.sh` (CLAUDE.md). ui-tester runs targeted UI tests during review: `./scripts/uitest.sh StudyReaderUITests/MetadataSheetTests StudyReaderUITests/ExternalOpenTests StudyReaderUITests/SettingsTests StudyReaderUITests/CategoryManagerTests/testCreateRenameAssignAndDeleteACategory`.

## Out of scope
A toast or banner for imports, changes to `ImportReport.summary` text, the password and large-file prompts, other Settings tabs, Settings for Review or Google, the tag manager's empty state, cover actions, the reader's own metadata entry point beyond what the shared sheet changes.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
