# T48: Import UI: drop targets, Dock icon, File > Import…, prompts, summary

- **Phase:** 1 (E1.1: F-02)
- **Agent:** ui-builder
- **Depends on:** T44, T47
- **ADRs:** docs/decisions/0016-import-pipeline-and-stored-files.md, docs/decisions/0017-reader-windows-and-commands.md (app-wide commands via AppSession)
- **Visual check needed:** yes

## Goal
Every way to start an import (SPEC F-02): drop files or folders onto the library window, drop onto the Dock icon (or "Open With" in Finder), File > Import… (⌘O). Answer the importer's questions (password, large file) with dialogs and show the summary.

## Files to touch
- `StudyReader/Features/Library/Import/ImportCoordinator.swift` (new)
- `StudyReader/Features/Library/Import/ImportPromptViews.swift` (new: password sheet, large-file alert, summary alert modifiers)
- `StudyReader/App/AppDelegate.swift` (new)
- `StudyReader/App/AppCommands.swift` (new)
- `StudyReader/App/StudyReaderApp.swift`, `StudyReader/App/AppSession.swift`, `StudyReader/App/RootView.swift` (modify)
- `StudyReaderTests/LibraryTests/ImportCoordinatorTests.swift` (new)

## Interfaces to produce
```swift
@MainActor @Observable
final class ImportCoordinator: ImportInteraction {
    struct PasswordRequest: Identifiable, Equatable { let id: UUID; let fileName: String }
    struct LargeFileRequest: Identifiable, Equatable { let id: UUID; let fileName: String; let byteCount: Int64 }

    /// Shows the folder-access panel; injected so tests never open a real panel.
    typealias FolderPanel = @MainActor (_ folder: URL, _ markdownFileName: String) async -> URL?
    init(importService: ImportService, folderPanel: @escaping FolderPanel = ImportCoordinator.showFolderAccessPanel)
    /// NSOpenPanel: canChooseDirectories true, canChooseFiles false, allowsMultipleSelection false,
    /// directoryURL = folder, message "Allow access to this folder so StudyReader can copy the images.",
    /// prompt "Allow". Returns the chosen URL or nil. Presented as a sheet on the main window when possible.
    static func showFolderAccessPanel(_ folder: URL, _ markdownFileName: String) async -> URL?
    private(set) var isImporting: Bool
    private(set) var passwordRequest: PasswordRequest?
    private(set) var largeFileRequest: LargeFileRequest?
    /// Summary of the last finished import; the UI shows it in an alert and sets it to nil when dismissed.
    var lastSummary: String?

    /// Queues the URLs; imports run one batch at a time in order (a second call while importing waits).
    func importURLs(_ urls: [URL])
    func answerPassword(_ password: String?)      // resumes the pending password continuation
    func answerLargeFile(_ allow: Bool)

    // ImportInteraction (called by ImportService; suspends on a CheckedContinuation until answered)
    func confirmLargeFile(named name: String, byteCount: Int64) async -> Bool
    func password(forFileNamed name: String) async -> String?
    /// Calls folderPanel (ADR-0016, user decision Q5). The importer decides when to ask (once per folder per batch).
    func requestFolderAccess(for folder: URL, markdownFileName: String) async -> URL?
}
```
- `AppSession` gets `let importCoordinator: ImportCoordinator` (built from `environment.importService`).
- `AppDelegate: NSObject, NSApplicationDelegate` with `@MainActor static var pendingURLs: [URL]` and `static var onOpenURLs: (@MainActor ([URL]) -> Void)?`. `application(_:open urls: [URL])`: if `onOpenURLs` is set call it, else append to `pendingURLs`. `StudyReaderApp` uses `@NSApplicationDelegateAdaptor(AppDelegate.self)`. When the session becomes ready (`LaunchView`/`RootView` `.task`), set `AppDelegate.onOpenURLs = { session.importCoordinator.importURLs($0) }` and flush `pendingURLs`. URLs whose scheme is the Google sign-in scheme are not files; ignore non-file URLs here (T72 handles them).
- `AppCommands: Commands`: `CommandGroup(replacing: .newItem) { Button("Import…") { … }.keyboardShortcut("o") }`. It needs the session: pass a closure from `StudyReaderApp` that sets `@State var showImporter` in the main window, or publish an `ImportActions` focused scene value from `RootView`; use the focused-value approach (`@FocusedValue(\.importActions)`), disabled when nil.
- Main window (`RootView`): `.dropDestination(for: URL.self) { urls, _ in session.importCoordinator.importURLs(urls); return true }` on the whole split view, with a highlighted drop overlay while targeted ("Drop to import"). `.fileImporter(isPresented:allowedContentTypes: [.pdf, UTType("net.daringfireball.markdown")!, .folder], allowsMultipleSelection: true)` → `importURLs`. Toolbar button "Import" (`plus`) in the library toolbar opens the same importer.
- Prompts (attached to the main window): password sheet with a `SecureField`, "Skip" and "Unlock" ("Enter the password for <file>"); large-file alert "<file> is larger than 500 MB. Import it anyway?" (Import / Skip); summary alert titled "Import finished" with `lastSummary` as the message. While `isImporting`, the library toolbar shows a small spinner.

## Tests (`ImportCoordinatorTests`, `@MainActor`, `AppEnvironment.inMemory()` + remove)
- `importsAndPublishesSummary`: `importURLs([plainMultiPage PDF])`; poll (bounded) until `lastSummary == "Imported 1"`; `isImporting == false`.
- `passwordRoundTrip`: import `encrypted(password: "secret")`; poll until `passwordRequest != nil` (file name matches); `answerPassword("secret")`; poll until `lastSummary == "Imported 1"`.
- `largeFileDecline`: build the coordinator over an `ImportService` created with `largeFileThreshold: 10` (construct it from the env's parts); answer `false`; summary contains "larger than 500 MB".
- `folderAccessUsesInjectedPanel`: coordinator built with a `folderPanel` closure that records its arguments and returns nil; `requestFolderAccess(for: someFolder, markdownFileName: "notes.md")` returns nil and the closure got exactly those arguments (no real panel opens).
- `batchesRunInOrder`: two `importURLs` calls back to back with different files → both documents exist; two summaries were produced in order (record them with a test hook: `var summaryHistory: [String]` `private(set)`, add it to the interface).

## Acceptance criteria
1. Imports run from the coordinator and report the summary; password and large-file questions round-trip. → tests `ImportCoordinatorTests/*`
2. Visual check (user), SPEC F-02 AC4: drag a PDF and an `.md` file onto the library window → both appear with covers (PDF) and "Imported 2" is shown. Drag a folder with nested files → supported files inside are imported. Drag a `.txt` → "Imported 0, skipped 1 (unsupported type)". Drag the same PDF again → "Already in library: …".
3. Visual check: drag a PDF onto the StudyReader Dock icon (app running) → it imports. Quit the app, drag a PDF onto the Dock icon (app not running) → the app launches and imports it after the library opens.
4. Visual check: File > Import… (⌘O) opens a picker that allows PDFs, Markdown files and folders, multiple selection; chosen files import.
5. Visual check: importing a password-protected PDF asks for the password once; the right password imports it, Skip skips it.
6. Visual check (SPEC F-03 AC4): drag a single `.md` file whose images sit in a sibling `images/` folder → a folder panel opens on the file's folder with "Allow access to this folder so StudyReader can copy the images."; Allow → the images show in the document; repeat with another file and Cancel → placeholders and the summary line "… couldn't be read and show(s) as placeholder(s)". Dragging the whole folder instead asks nothing.
7. Visual check: T47's deferred checks 1–4 (grid/list fields, sorts and filters, delete and Reveal in Finder, failed-extraction badge), now with real documents.

## Out of scope
- Import logic (T41). Metadata editing (T50). Reader opening after import (not in SPEC).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-25, Sonnet (code-reviewer, effort medium): CHANGES REQUESTED once: Library root log line was privacy .public (ARCHITECTURE §14). Fixed with .private (ui-builder re-run at effort high); line confirmed in diff. Otherwise APPROVED: first review APPROVED; fixes for Open With (LSMultipleInstancesProhibited, ExternalURLRouter) and landscape covers reviewed. 328 tests pass, 0 warnings. Visual checks for Open With and landscape cover deferred to the T52 checkpoint (VISUAL_CHECKS.md).
