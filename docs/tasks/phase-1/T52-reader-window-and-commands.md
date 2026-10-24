# T52: Reader tabs, toolbar, menu commands, open from the library

- **Phase:** 1 (E1.2/E1.3 reader chrome: F-01 document tabs, F-04 commands, F-06 current color, SPEC §5 shortcuts)
- **Agent:** ui-builder
- **Depends on:** T47, T48, T51
- **ADRs:** docs/decisions/0017-reader-windows-and-commands.md (read in full; user decision Q2: native window tabs)
- **Visual check needed:** yes

## Goal
Documents open as native macOS window tabs in the main window's tab group (ADR-0017, SPEC F-01): the library is the first tab, each document is a tab after it, opening an already open document selects its tab, and tabs can be dragged out into their own windows as macOS allows. Each reader tab is a SwiftUI `WindowGroup` window joined to the main window's tab group. This task builds the reader shell: tabbing, loading/error states, a content slot the engines fill (T53 PDF, T55 Markdown), the toolbar (current highlight color, right-panel toggle), the menu commands wired through `FocusedValue`, and "Open" from the library.

**No custom tab bar.** Use native window tabbing only. If neither SwiftUI nor the AppKit settings below (`NSWindow.tabbingMode`, `tabbingIdentifier`, `addTabbedWindow(_:ordered:)`) can make reader windows join the main window's tab group on macOS 27, stop and report BLOCKED with what you tried.

## Files to touch
- `StudyReader/Features/Reader/ReaderWindowView.swift` (new)
- `StudyReader/Features/Reader/ReaderActions.swift` (new: FocusedValue)
- `StudyReader/App/ReaderTabbing.swift` (new: tabbing helper + window accessor)
- `StudyReader/App/StudyReaderApp.swift` (modify: reader `WindowGroup`)
- `StudyReader/App/RootView.swift` (modify: apply the tabbing accessor to the main window)
- `StudyReader/App/AppCommands.swift` (modify: View, Edit and Document menu commands)
- `StudyReader/Features/Library/LibraryView.swift` (modify: Open / double-click / Return → router)
- `StudyReaderTests/AppTests/ReaderTabbingTests.swift` (new)

## Interfaces to produce
```swift
/// Published by the selected reader tab with .focusedSceneValue (ADR-0017).
struct ReaderActions {
    let model: ReaderModel
    let windowState: ReaderWindowState
}
extension FocusedValues { @Entry var readerActions: ReaderActions? }

/// View-only state of one reader tab (not part of ReaderModel).
@MainActor @Observable
final class ReaderWindowState {
    var isMetadataSheetPresented = false
}

struct ReaderWindowView: View {
    init(documentId: String, launchModel: AppLaunchModel)
}

/// Native window tabbing for the main window and reader windows (ADR-0017).
@MainActor
enum ReaderTabbing {
    static let identifier = "StudyReaderMain"
    /// window.tabbingMode = .preferred; window.tabbingIdentifier = identifier.
    static func configure(_ window: NSWindow)
    /// configure(window); then, if another visible window with `identifier` exists and `window` isn't already in
    /// its tab group, add `window` after the last window of the main window's tab group
    /// (`last.addTabbedWindow(window, ordered: .above)`) and make it key (selects the tab). The main window is the
    /// one whose `identifier` (NSUserInterfaceItemIdentifier) SwiftUI gave the "main" scene; if you can't find it
    /// reliably, use the first window in `NSApp.windows` with tabbingIdentifier == identifier that isn't `window`.
    static func joinMainTabGroup(_ window: NSWindow)
}

/// Zero-size NSViewRepresentable; calls `onWindow` once from viewDidMoveToWindow with the hosting NSWindow.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void
}
```
- The main window: `RootView` adds `.background(WindowAccessor { ReaderTabbing.configure($0) })`, so the library window is the tab group's first window.
- `StudyReaderApp` adds:
  ```swift
  WindowGroup(id: ReaderRouter.windowId, for: String.self) { $documentId in
      ReaderWindowRoot(documentId: documentId, launchModel: launchModel)   // waits for launchModel.session
  }
  ```
  (no `.defaultSize`: the tab takes the group's frame). `ReaderWindowRoot` adds `.background(WindowAccessor { ReaderTabbing.joinMainTabGroup($0) })`. A nil `documentId` (state restoration without a value) shows "No document" and nothing else.
- Opening: `session.router.open(documentId:at:using: openWindow)` (T51). For an equal value SwiftUI reuses the existing window; `joinMainTabGroup` isn't called again, so additionally call `window.makeKeyAndOrderFront(nil)` from `ReaderWindowRoot` when a new pending location arrives for an already open document (it selects that tab). Opening the same document twice never creates a second tab.
- Tabs dragged out into their own window keep working (each reader window is independent). Don't prevent dragging out or merging.
- `ReaderWindowView` owns `@State var model: ReaderModel` (created once from the session), runs `.task { await model.load() }` and `.task { await model.observeHighlights() }`, calls `model.receiveRouterLocation()` from `.onChange(of: session.router.pendingLocations[documentId])`, and `Task { await model.flushPosition() }` in `.onDisappear` (closing a tab closes its window). Tab title = document title (`.navigationTitle`), subtitle = category name.
- Content: `.loading` → `ProgressView`; `.failed(message)` → `ContentUnavailableView` with the message; `.ready` → `ReaderContentSlot(model:)`, a view with a `switch model.document?.fileType` that shows `Text("PDF reader arrives in T53")` / `Text("Markdown reader arrives in T55")` placeholders; T53 and T55 replace exactly those two branches.
- Right side: when `model.isRightPanelVisible`, an `HSplitView`/inspector-style column (min 260, ideal 300) with a `Picker` of `ReaderPanelTab` (Highlights / Notes) and a placeholder body ("arrives in T63").
- Toolbar: current color menu (five `HighlightPalette` swatches with the color labels; checkmark on `settings.currentColor`; selecting sets it); "Highlights" toggle button (`sidebar.right`) bound to `isRightPanelVisible`; snapshot and find buttons appear only when `model.engineActions.startSnapshot` / `findInDocument` are non-nil.
- `model.transientMessage` shows as a small banner at the bottom for 3 s (a view-level `.task(id: message)` with `try? await Task.sleep(for: .seconds(3))` is allowed here: it's view code, not logic).
- `AppCommands` additions (all read `@FocusedValue(\.readerActions)`; disabled when nil, i.e. when the library tab is selected, or when the engine action is nil):
  - View menu: Zoom In ⌘+ (`"+"` and `"="` both), Zoom Out ⌘−, Actual Size ⌘0, Fit Width ⌘9, Single Page (toggle), Show Thumbnails, Highlights Panel ⌥⌘H (toggles `isRightPanelVisible` with tab `.highlights`).
  - Edit menu: Find in Document ⌘F (`engineActions.findInDocument`).
  - A "Document" menu: Snapshot ⌃⌘S (`startSnapshot`).
  - Edit Metadata… ⇧⌘M already exists from T50 (library). Change that one command (don't add a second command with the same shortcut): if `readerActions` is non-nil, set `windowState.isMetadataSheetPresented = true` (`ReaderWindowView` presents T50's `MetadataSheet` for `model.documentId` with `currentPageIndex: model.engineActions.currentPageIndex?()`); otherwise use `libraryActions` as before. Don't change T51's API.
  - Keep the system's tab commands (Show Tab Bar, Merge All Windows, Move Tab to New Window); don't remove them.
- Library: `openDocument(_ id:)` (left by T47) calls `session.router.open(documentId: id, using: openWindow)` (`@Environment(\.openWindow)`). Context menu Open and double-click/Return use it.

## Tests (`ReaderTabbingTests`, `@MainActor`)
- `configureSetsPreferredTabbing`: a new `NSWindow` → after `configure`, `tabbingMode == .preferred` and `tabbingIdentifier == "StudyReaderMain"`.
- `joinConfiguresEvenWithoutGroup`: `joinMainTabGroup` on a window when no other StudyReader window exists → configured, no crash, `tabbedWindows` is nil or contains only it.

(Actual tab grouping needs on-screen windows and is covered by the visual check.)

## Acceptance criteria
1. Window tabbing settings are applied. → tests `ReaderTabbingTests/*`
2. Visual check (user), SPEC F-01 AC4: with the library open, double-click a document → it opens as a new tab after the Library tab, titled with the document's title, showing the placeholder for its type; double-click a second document → a third tab; double-click the first document again → its tab is selected and no new tab appears; the Library tab stays first.
3. Visual check: drag a document tab out of the tab bar → it becomes its own window and still works; drag it back (or Window > Merge All Windows) → it rejoins the group. Closing a tab closes only that document.
4. Visual check: the toolbar color menu shows the five colors with labels from Settings; the choice persists across relaunch; the Highlights button toggles a right column with Highlights/Notes tabs; ⌥⌘H toggles it too.
5. Visual check: with a document tab selected, View menu zoom items are disabled until T53 (expected); ⇧⌘M opens the Edit Metadata sheet for that document; with the Library tab selected, ⇧⌘M edits the selected library document.
6. Visual check: delete a document from the Library tab while its tab is open, quit, and relaunch (macOS restores the tab) → the restored tab shows "This document is no longer in the library."
7. Full suite passes (logic tests are in T51).

## Out of scope
- PDF and Markdown content (T53, T55), panel content (T63), popover (T62), find UI (T67). A custom tab bar (forbidden, ADR-0017).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
