# T92b: Settings > Google: no folder-link field, "Open in Drive" for the StudyReader folder, one-time notice

- **Phase:** 1 (bug hunt `docs/bugs/phase-1.md` H2; user decision 2026-10-28; SPEC F-21, F-22 "Google" as amended)
- **Agent:** ui-builder. Escalation (CLAUDE.md): Sonnet agent. 1st rejection → same agent, effort `high`, with the spec and the review report. 2nd rejection → stop and ask the user. Reviews after an escalation run code-reviewer with effort `high`.
- **Depends on:** T92a (the service no longer reads the pasted folder; `SettingsStore.googleAppFolderId(forAccount:)` exists)
- **ADRs:** ADR-0018 (+ amendment 2026-10-28 "app folder"), ADR-0015
- **Visual check needed:** yes (Mac rows "T92 (1)"/"T92 (2)" in VISUAL_CHECKS.md already list the end-to-end checks; the orchestrator adds a "T92b" look row from the report: the Export folder section signed in, before and after the first export, and the one-time notice)
- **UI tests:** this task changes one existing UI-test expectation (`SettingsTests/testGoogleTabShowsNotConfiguredAndHidesFolderAndTargets`, see below). The implementer does NOT run UI tests. After T95, at the closing state, ui-tester runs ONE targeted UI run: `./scripts/uitest.sh StudyReaderUITests/SettingsTests` (docs/tasks/phase-1/README.md, closing steps).

## Goal
With T92a every new Doc goes into the app's own "StudyReader" folder, so the pasted folder link in Settings > Google is dead. Remove the field and its parser, show where exports go with an "Open in Drive" link to the folder once it exists, and tell the user once if an older version had a pasted folder saved.

## Files to touch
- `StudyReader/Features/Settings/GoogleSettingsView.swift` (modify: `folderSection`, `.task`)
- `StudyReader/Features/Export/ExportTargetsModel.swift` (modify: remove `folderLink`, `folderError`, `saveFolder`; add the members below)
- `StudyReader/App/AppSettings.swift` (modify: remove `googleExportFolderId`)
- `StudyReader/Core/Support/SettingsStore.swift` (modify: rename `googleExportFolderId` → `legacyGoogleExportFolderId`, same key string `"settings.googleExportFolderId"`, same get/set behaviour)
- `StudyReader/Features/Export/DriveFolderLink.swift` (delete), `StudyReaderTests/ExportTests/DriveFolderLinkTests.swift` (delete)
- `StudyReaderTests/ExportTests/ExportTargetsModelTests.swift`, `StudyReaderTests/CoreTests/SettingsStoreTests.swift`, `StudyReaderTests/AppTests/AppSettingsTests.swift` (modify)
- `StudyReaderUITests/SettingsTests.swift` (modify: one assertion, see AC 7). Checked by the architect: no other UI test references the folder field (`ExportSheetTests`, `HighlightsBrowserTests` and the rest don't).
- Existing unit tests that change, in summary: `DriveFolderLinkTests` (deleted), `ExportTargetsModelTests/folderLinkParsing` (replaced), the folder assertions in `SettingsStoreTests` and `AppSettingsTests` (renamed/removed). T92a already changed the `GoogleExportServiceTests` folder test and `ExportSheetModelTests/exportShowsOutcome`.
- `StudyReader/Resources/Localizable.xcstrings` only if your build rewrites it (don't hand-edit)
- You may touch other files if the diagnosis requires it; list each one and the reason in the report.

## Interfaces to produce
New members of `ExportTargetsModel` (stored properties in the class itself):
```swift
/// The StudyReader folder's ID for the account last passed to `refreshAppFolder(account:)` (nil when signed out or
/// before the first export). Read from `SettingsStore.googleAppFolderId(forAccount:)`.
private(set) var appFolderId: String?
/// Re-reads `appFolderId` for `email` (nil email → nil) and remembers `email` for the refresh after an export.
func refreshAppFolder(account email: String?)
/// true after `consumeLegacyFolderNotice()` found a pasted folder ID saved by an older build.
private(set) var showsLegacyFolderNotice = false
/// Reads and removes the legacy key; sets `showsLegacyFolderNotice` when it held a non-empty value.
func consumeLegacyFolderNotice()
/// https://drive.google.com/drive/folders/<id>
nonisolated static func folderURL(folderId: String) -> URL
```
`SettingsStore.legacyGoogleExportFolderId: String?` (get; nonmutating set, nil removes) replaces `googleExportFolderId`. Nothing else may read it; only `consumeLegacyFolderNotice()` and tests use it.

## What to do
1. **Remove the pasted folder.** Delete `DriveFolderLink` and its tests; remove `folderLink`, `folderError`, `saveFolder()` from `ExportTargetsModel`; remove `AppSettings.googleExportFolderId`; rename the store property as above. Grep the app and test targets for `googleExportFolderId`, `DriveFolderLink`, `folderLink`, `saveFolder` and "Export folder link": none may remain except `legacyGoogleExportFolderId` and the raw key string in `GoogleExportServiceTests/appFolderOldSettingsAreIgnored` (T92a).
2. **Export folder section** (shown only when configured, as today):
   - Line: "Exports go to the StudyReader folder in your Google Drive." (secondary/callout like today's hint).
   - If `appFolderId != nil`: a button "Open in Drive" (`NSWorkspace.shared.open(ExportTargetsModel.folderURL(folderId:))`), accessibility label "Open the StudyReader folder in Google Drive". Otherwise the text "It's created on your first export." No text field.
   - Signed out: show the line without the button.
   - If `showsLegacyFolderNotice`: one more line, "The export folder link you saved earlier isn't used anymore. New Docs go to the StudyReader folder.", accessibility label equal to the text.
3. **Refresh points.** In `GoogleSettingsView`: after `model.refresh()` in the existing `.task`, call `targets.refreshAppFolder(account: model.email)` and, only when `model.state != .notConfigured`, `targets.consumeLegacyFolderNotice()`; add `.onChange(of: model.email)` → `refreshAppFolder`; in the existing `didBecomeActive` handler refresh it after `model.refresh()`. In `ExportTargetsModel`, `exportNow` and `createNewDoc` re-read the folder for the last account passed to `refreshAppFolder` when they finish.
4. **Notice once.** `consumeLegacyFolderNotice()`: if `legacyGoogleExportFolderId` is non-nil (after trimming, non-empty), set `showsLegacyFolderNotice = true`; in all cases remove the legacy key. Not in `init` (SwiftUI may build the model more than once).
5. **Historical specs** (T70, T73, T89) are records; don't edit them.

## Acceptance criteria
1. `ExportTargetsModelTests/appFolderFollowsTheAccount` (replaces `folderLinkParsing`): with `settingsStore.setGoogleAppFolderId("F1", forAccount: "a@example.com")`, `refreshAppFolder(account: "a@example.com")` → `appFolderId == "F1"`; `refreshAppFolder(account: "b@example.com")` → nil; `refreshAppFolder(account: nil)` → nil; `ExportTargetsModel.folderURL(folderId: "F1").absoluteString == "https://drive.google.com/drive/folders/F1"`.
2. `ExportTargetsModelTests/legacyFolderNoticeShowsOnce`: `settingsStore.legacyGoogleExportFolderId = "PASTED123"`; first `consumeLegacyFolderNotice()` → `showsLegacyFolderNotice == true` and the key is gone (`defaults.object(forKey: "settings.googleExportFolderId") == nil`); a new model's `consumeLegacyFolderNotice()` → false. With no legacy value → false.
3. `ExportTargetsModelTests/exportNowRefreshesTheAppFolder`: refresh for `student@example.com` (nil folder), run `exportNow` on a target with a stub HTTP flow that creates the folder (`[about, {"files":[]}, {"id":"APPFOLDER"}, {"id":"FILE1"}]`, `StubGoogleAuth()`) → afterwards `appFolderId == "APPFOLDER"`.
4. `ExportTargetsModelTests/statusTexts`, `exportNowIgnoresASecondCallForTheSameTarget`, `exportNowDoesNotBlockADifferentTarget`, `removeKeepsDoc` pass unchanged.
5. `SettingsStoreTests` and `AppSettingsTests`: the old `googleExportFolderId` assertions are replaced by `legacyGoogleExportFolderId` round-trip and nil-removes checks in `SettingsStoreTests` (same key string); `AppSettingsTests` no longer mention a folder. All other assertions unchanged.
6. `DriveFolderLinkTests` is deleted with `DriveFolderLink.swift`; the grep in "What to do" 1 finds nothing else (reviewer runs it on the diff).
7. `StudyReaderUITests/SettingsTests.swift` line 66: replace the `textFields["Export folder link"]` assertion with exactly `XCTAssertFalse(window.staticTexts["Exports go to the StudyReader folder in your Google Drive."].exists, "The unconfigured Google tab shows the export folder section.")`. Nothing else in the file changes; the test name stays. Verified at the closing targeted UI run (`SettingsTests`), not by the implementer.
8. `./scripts/test.sh StudyReaderTests/ExportTargetsModelTests StudyReaderTests/SettingsStoreTests StudyReaderTests/AppSettingsTests StudyReaderTests/GoogleExportServiceTests` passes; `./scripts/build.sh` succeeds (it doesn't compile the UI-test target; the reviewer reads the `SettingsTests` change).
9. Visual check (Mac, Google account; rows "T92 (1)", "T92 (2)" and the T92b look row): Settings > Google signed in before any export shows the line and "It's created on your first export.", no text field; after the first export "Open in Drive" opens the folder in the browser; an older build's pasted folder shows the notice once, not after reopening Settings; light and dark.

## Out of scope
- Any export-service change (T92a, T94); the Google Picker (BACKLOG B51); moving Docs between folders.
- Other Settings tabs; the targets table.

## Review log
<!-- Main session appends one line per review: date, implementer <agent> <model> <effort> (reworks: effort), reviewer <agent> <model> <effort>: VERDICT, reason -->
