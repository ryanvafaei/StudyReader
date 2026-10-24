# T52: Reader window, toolbar, menu commands, open from the library

- **Phase:** 1 (E1.2/E1.3 reader chrome: F-04 commands, F-06 current color, SPEC §5 shortcuts)
- **Agent:** ui-builder
- **Depends on:** T47, T48, T51
- **ADRs:** docs/decisions/0017-reader-windows-and-commands.md (read in full)
- **Visual check needed:** yes

## Goal
Documents open in their own window (ADR-0017). This task builds the window shell: loading/error states, a content slot the engines fill (T53 PDF, T55 Markdown), the toolbar (current highlight color, right-panel toggle), the Reader menu commands wired through `FocusedValue`, and "Open" from the library.

## Files to touch
- `StudyReader/Features/Reader/ReaderWindowView.swift` (new)
- `StudyReader/Features/Reader/ReaderActions.swift` (new: FocusedValue)
- `StudyReader/App/StudyReaderApp.swift` (modify: reader `WindowGroup`)
- `StudyReader/App/AppCommands.swift` (modify: Reader and View menu commands)
- `StudyReader/Features/Library/LibraryView.swift` (modify: Open / double-click / Return → router)

## Interfaces to produce
```swift
/// Published by the focused reader window with .focusedSceneValue (ADR-0017).
struct ReaderActions {
    let model: ReaderModel
    let windowState: ReaderWindowState
}
extension FocusedValues { @Entry var readerActions: ReaderActions? }

/// View-only state of one reader window (not part of ReaderModel).
@MainActor @Observable
final class ReaderWindowState {
    var isMetadataSheetPresented = false
}

struct ReaderWindowView: View {
    init(documentId: String, launchModel: AppLaunchModel)
}
```
- `StudyReaderApp` adds:
  ```swift
  WindowGroup(id: ReaderRouter.windowId, for: String.self) { $documentId in
      ReaderWindowRoot(documentId: documentId, launchModel: launchModel)   // waits for launchModel.session
  }
  .defaultSize(width: 1000, height: 760)
  ```
  A nil `documentId` (state restoration without a value) shows "No document" and nothing else.
- `ReaderWindowView` owns `@State var model: ReaderModel` (created once from the session), runs `.task { await model.load() }` and `.task { await model.observeHighlights() }`, calls `model.receiveRouterLocation()` from `.onChange(of: session.router.pendingLocations[documentId])`, and `Task { await model.flushPosition() }` in `.onDisappear`. Window title = document title (`.navigationTitle`), subtitle = category name.
- Content: `.loading` → `ProgressView`; `.failed(message)` → `ContentUnavailableView` with the message; `.ready` → `ReaderContentSlot(model:)`, a view with a `switch model.document?.fileType` that shows `Text("PDF reader arrives in T53")` / `Text("Markdown reader arrives in T55")` placeholders; T53 and T55 replace exactly those two branches.
- Right side: when `model.isRightPanelVisible`, an `HSplitView`/inspector-style column (min 260, ideal 300) with a `Picker` of `ReaderPanelTab` (Highlights / Notes) and a placeholder body ("arrives in T63").
- Toolbar: current color menu (five `HighlightPalette` swatches with the color labels; checkmark on `settings.currentColor`; selecting sets it); "Highlights" toggle button (`sidebar.right`) bound to `isRightPanelVisible`; snapshot and find buttons appear only when `model.engineActions.startSnapshot` / `findInDocument` are non-nil.
- `model.transientMessage` shows as a small banner at the bottom for 3 s (a view-level `.task(id: message)` with `try? await Task.sleep(for: .seconds(3))` is allowed here: it's view code, not logic).
- `AppCommands` additions (all read `@FocusedValue(\.readerActions)`; disabled when nil or when the engine action is nil):
  - View menu: Zoom In ⌘+ (`"+"` and `"="` both), Zoom Out ⌘−, Actual Size ⌘0, Fit Width ⌘9, Single Page (toggle), Show Thumbnails, Highlights Panel ⌥⌘H (toggles `isRightPanelVisible` with tab `.highlights`).
  - Edit menu: Find in Document ⌘F (`engineActions.findInDocument`).
  - A "Document" menu: Snapshot ⌃⌘S (`startSnapshot`).
  - Edit Metadata… ⇧⌘M already exists from T50 (library). Change that one command (don't add a second command with the same shortcut): if `readerActions` is non-nil, set `windowState.isMetadataSheetPresented = true` (`ReaderWindowView` presents T50's `MetadataSheet` for `model.documentId` with `currentPageIndex: model.engineActions.currentPageIndex?()`); otherwise use `libraryActions` as before. Don't change T51's API.
- Library: `openDocument(_ id:)` (left by T47) calls `session.router.open(documentId: id, using: openWindow)` (`@Environment(\.openWindow)`). Context menu Open and double-click/Return use it.

## Acceptance criteria
1. Visual check (user): double-click a document in the library → a new window titled with the document's title opens with the placeholder for its type; double-clicking it again brings the same window to the front (no second window); two different documents open two windows.
2. Visual check: the toolbar color menu shows the five colors with labels from Settings; the choice persists across relaunch; the Highlights button toggles a right column with Highlights/Notes tabs; ⌥⌘H toggles it too.
3. Visual check: with a reader focused, View menu zoom items are disabled until T53 (expected); ⇧⌘M opens the Edit Metadata sheet for that document; with the library focused, ⇧⌘M edits the selected library document.
4. Visual check: delete a document while its window is open, then reopen the window from Window menu restoration → "This document is no longer in the library."
5. Full suite passes (logic tests are in T51).

## Out of scope
- PDF and Markdown content (T53, T55), panel content (T63), popover (T62), find UI (T67).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
