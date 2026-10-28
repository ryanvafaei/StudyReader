# T73: Export UI: Export Highlights sheet, export targets, folder setting, Export selection

- **Phase:** 1 (E1.8: F-21 UI, F-22 Google tab, F-13 "export selection")
- **Agent:** ui-builder
- **Depends on:** T69, T72
- **ADRs:** docs/decisions/0018-google-export-seams-and-status.md, docs/decisions/0017-reader-windows-and-commands.md (LibraryActions)
- **Visual check needed:** yes (manual, with the user's Google credentials, which are already set up)

## Goal
Let the user export: an "Export Highlights…" sheet (scope + options) from the library context menu and the File menu; the export targets list and export folder in Settings > Google (last exported, status, Open in Google Docs, Export now, Keep in sync, Remove, Create new Doc); and "Export Selection" in the highlights browser.

## Files to touch
- `StudyReader/Features/Export/ExportSheetModel.swift` (new)
- `StudyReader/Features/Export/ExportSheet.swift` (new)
- `StudyReader/Features/Export/ExportTargetsModel.swift` (new)
- `StudyReader/Features/Settings/GoogleSettingsView.swift` (modify: folder + targets sections)
- `StudyReader/Features/Library/LibraryView.swift`, `StudyReader/Features/HighlightsBrowser/HighlightsBrowserView.swift`, `StudyReader/App/AppCommands.swift` (modify)
- `StudyReaderTests/ExportTests/ExportSheetModelTests.swift`, `ExportTargetsModelTests.swift` (new)

## Interfaces to produce
```swift
@MainActor @Observable
final class ExportSheetModel {
    enum ScopeKind: String, CaseIterable { case document, tag, category, themedReview, all }
    init(session: AppSession, initialScope: ExportScope?)       // e.g. .document(id) from the library
    var scopeKind: ScopeKind
    var selectedId: String?                                     // document/tag/category/themed review id
    var options = ExportOptions()                               // prefilled from an existing target for the scope
    private(set) var documents: [LibraryDocument] = []; private(set) var tags: [LibraryTag] = []
    private(set) var categories: [DocumentCategory] = []; private(set) var themedReviews: [ThemedReview] = []
    private(set) var isExporting = false
    private(set) var outcome: ExportOutcome?
    var scope: ExportScope? { get }                             // nil until a required id is chosen
    var canExport: Bool { get }
    func load() async
    func export() async                                         // googleExportService.exportScope(scope!, options:)
    /// User text for outcome: exported → "Exported. The Google Doc is up to date."; queued → "You're offline.
    /// The export will run when you're back online."; signInRequired → "Sign in to Google in Settings > Google.";
    /// docMissing → "The Google Doc was deleted or you lost access."; notConfigured → "Google export not configured.";
    /// failed(text) → text.
    var outcomeMessage: String? { get }
}

@MainActor @Observable
final class ExportTargetsModel {
    init(session: AppSession)
    private(set) var targets: [ExportTarget] = []
    var folderLink: String                                      // shows settings.googleExportFolderId
    private(set) var folderError: String?
    func observe() async
    /// DriveFolderLink.folderId(from:); nil → folderError "That isn't a Google Drive folder link."; empty → clears.
    func saveFolder() 
    func exportNow(_ id: String) async
    func setKeepInSync(_ id: String, _ on: Bool) async
    func remove(_ id: String) async                             // never deletes the Doc
    func createNewDoc(_ id: String) async                       // clearFileId then exportNow
    nonisolated static func docURL(fileId: String) -> URL       // https://docs.google.com/document/d/<id>/edit
    nonisolated static func statusText(_ target: ExportTarget) -> String   // "Never exported" / "Exported <relative>" /
                                                                // "Waiting for network" / "Failed: <lastError>" /
                                                                // "Doc missing" / "Sign-in required"
}
```
Not configured (ADR-0018): when `googleAuth.isConfigured` is false (`GOOGLE_CLIENT_ID` empty at runtime, so `GIDClientID` is empty), the Export sheet shows "Google export not configured" instead of the Export button, Settings > Google shows the same text (from T72) and hides the folder and targets sections, and "Export Selection…" shows it in an alert. No request is made. Credentials come only from the `GOOGLE_CLIENT_ID` / `GOOGLE_REVERSED_CLIENT_ID` build settings via Info.plist; never read `Secrets/`.

Views:
- `ExportSheet` (width 440): Scope picker (Document / Tag / Category / Themed review — hidden when there are none — / All highlights) with a second picker for the id; toggles "Include highlight notes", "Include document notes", "Include image highlights as placeholders"; "Group by" (Document / Tag); Cancel / Export. While exporting, a spinner; afterwards the outcome message, plus "Open in Google Docs" when exported and "Create New Doc" when `docMissing`.
- Library context menu "Export Highlights…" (enable the T47 hook; `LibraryActions.exportHighlights`) opens the sheet with `.document(id)`. File menu "Export Highlights…" (⇧⌘E) opens it with no initial scope (defaults to All highlights).
- Settings > Google (below T72's account section): "Export folder" text field + "Save" (paste a folder link; empty = My Drive root) and a targets `Table`: Title, Last exported / status (`statusText`), Keep in sync toggle, buttons Open in Google Docs (when `googleFileId` exists; `NSWorkspace.shared.open(docURL)`), Export Now, Remove (confirmation "Remove this export target? The Google Doc isn't deleted."), and Create New Doc when status is `docMissing`.
- Highlights browser bulk bar: "Export Selection…" → `googleExportService.exportSelection(highlightIds:options: ExportOptions())`, outcome shown in an alert.

## Tests
`ExportSheetModelTests` (`@MainActor`, in-memory environment whose `googleExportService` uses `StubHTTPClient` + configured `StubGoogleAuth` from T71's test support; build the environment with those stubs through the initializer):
- `scopeRequiresId`: kind `.tag` with no id → `canExport == false`; with id → `scope == .tag(id)`.
- `optionsPrefillFromExistingTarget`: an existing target for `.all` with `includeImages: false` → after `load()` with `.all`, `options.includeImages == false`.
- `exportShowsOutcome`: stub create → `outcome == .exported("FILE1")`, `outcomeMessage` is the exported text.
- `notConfiguredMakesNoRequest`: environment with `UnconfiguredGoogleAuth` → `export()` gives `outcome == .notConfigured`, `outcomeMessage == "Google export not configured."`, and the stub HTTP client recorded no request.
`ExportTargetsModelTests`:
- `folderLinkParsing`: valid link → `settings.googleExportFolderId` set; invalid → `folderError`; empty → cleared.
- `statusTexts`: each `ExportStatus` maps to its text.
- `removeKeepsDoc`: `remove` deletes the row and sends no request.

## Acceptance criteria
1. Sheet and targets logic behave as specified. → tests `ExportSheetModelTests/*`, `ExportTargetsModelTests/*`
2. Visual check (user), SPEC F-21 AC4 (credentials are already set up; sign in via T72 first): export one lecture document → a Google Doc titled "StudyReader – <title>" appears in My Drive (or the chosen folder) with the expected structure; add highlights, use Export Now → the same Doc updates (same URL); add the Doc as a source in Gemini Notebook and confirm it shows the highlights.
3. Visual check: turn Wi-Fi off and export → "You're offline…" and the target shows "Waiting for network"; delete the Doc in Drive and Export Now → "Doc missing" with Create New Doc working; Remove leaves the Doc in Drive.
4. Visual check: select three highlights in the browser → Export Selection… creates a one-off Doc and no new target appears.

## Out of scope
- Keep-in-sync scheduling and the automatic retry when back online (T74; the toggle is stored here).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-28, implementer ui-builder Sonnet medium (no reworks), reviewer code-reviewer Sonnet medium: APPROVED (conditional on the full unit run). Export sheet, targets and folder settings, Export Selection met; not-configured paths make no request; sheet cannot double-submit; 7 unit tests ran on CI; 3 UI tests unrun (T74 checkpoint compiles/runs them). Minor items to BACKLOG B33.
