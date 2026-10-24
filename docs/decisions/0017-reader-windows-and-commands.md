# ADR-0017: Reader tabs, navigation and commands

- Status: Accepted (window model decided by the user 2026-10-24, Phase 1 Q2: native window tabs)
- Date: 2026-10-24 (Phase 1 planning)

## Context
SPEC defines the main window (sidebar + content) but not where a document opens. Search results, the highlights browser and the highlights panel must open a document at a location. Menu shortcuts (zoom, snapshot, highlights panel, metadata) act on whichever reader is focused. PDFKit and NSTextView are AppKit, the chrome is SwiftUI, and PDFKit objects must stay on the main actor.

## Decision
- Each document opens as a **native macOS window tab in the main window's tab group** (user decision). Technically each reader is still its own window: `WindowGroup(id: "reader", for: String.self)` with the document ID as value. The library window (`Window(id: "main")`) is always the first tab.
- Tabbing is set on the AppKit windows: the main window and every reader window get `tabbingMode = .preferred` and `tabbingIdentifier = "StudyReaderMain"` (`ReaderTabbing.identifier`). A new reader window is added to the end of the existing tab group (`lastWindowInGroup.addTabbedWindow(newWindow, ordered: .above)`) and selected. The settings are applied from SwiftUI through a small `NSViewRepresentable` window accessor, because SwiftUI has no tabbing API for these scenes. If neither SwiftUI nor this AppKit route can control tabbing on macOS 27, the implementer reports BLOCKED. Never build a custom tab bar.
- Opening an already open document switches to its tab (SwiftUI's `openWindow(id:value:)` reuses the window for an equal value; bring it front with `makeKeyAndOrderFront`, which selects the tab). Users can drag tabs out into their own windows and back, as macOS allows; the app doesn't restrict that.
- `ReaderRouter` (`@MainActor @Observable`, owned by `AppSession`) stores a pending `ReaderLocation` per document ID. Callers use `router.open(documentId:at:using: openWindow)`. The tab's `ReaderModel` takes the pending location on load and whenever a new one arrives.
- `ReaderLocation`: `.page(Int)`, `.highlight(String)`, `.searchHit(unitIndex: Int, query: String)`, `.documentNote`.
- One `@MainActor @Observable ReaderModel` per reader tab is the only bridge between the AppKit engines and SwiftUI. Engines report selections, clicks and positions to it. It holds UI requests (`HighlightPopoverRequest`, `SelectionToolbarRequest`) that SwiftUI presents. Engines register their commands as `ReaderEngineActions` closures on the model.
- Menu commands use `FocusedValue`: the selected reader tab publishes `ReaderActions`; the library tab publishes `LibraryActions`. App-wide commands (Import ⌘O, Search ⌘⇧F) go through `AppSession`; Search selects the library tab.
- Popover anchors are rects in the reader content view's coordinate space (top-left origin), which SwiftUI uses as `.popover(attachmentAnchor: .rect(.rect(...)))`.
- Closing a tab closes that reader window; it flushes the reading position first.

## Alternatives considered
- One separate window per document (the first proposal): replaced by tabs at the user's request.
- Reader inside the main window's detail column: one document at a time, and the sidebar takes reading width.
- A custom SwiftUI tab bar: duplicates what macOS provides (drag-out, merge, Window menu) and is ruled out.

## Consequences
- Documents and the library share one window frame by default; the main window's minimum size (`MainWindowLayout`) applies to the group.
- Commands that only make sense in a reader are disabled when the library tab is selected.
