# ADR-0017: Reader windows, navigation and commands

- Status: Accepted (window model pending user confirmation, Phase 1 open question Q2)
- Date: 2026-10-24 (Phase 1 planning)

## Context
SPEC defines the main window (sidebar + content) but not where a document opens. Search results, the highlights browser and the highlights panel must open a document at a location. Menu shortcuts (zoom, snapshot, highlights panel, metadata) act on whichever reader is focused. PDFKit and NSTextView are AppKit, the chrome is SwiftUI, and PDFKit objects must stay on the main actor.

## Decision
- Each document opens in its own window: `WindowGroup(id: "reader", for: String.self)`, where the value is the document ID. Opening an already open document brings its window to the front.
- `ReaderRouter` (`@MainActor @Observable`, owned by `AppSession`) stores a pending `ReaderLocation` per document ID. Callers use `router.open(documentId:at:using: openWindow)`. The window's `ReaderModel` takes the pending location on load and whenever a new one arrives.
- `ReaderLocation`: `.page(Int)`, `.highlight(String)`, `.searchHit(unitIndex: Int, query: String)`, `.documentNote`.
- One `@MainActor @Observable ReaderModel` per window is the only bridge between the AppKit engines and SwiftUI. Engines report selections, clicks and positions to it. It holds UI requests (`HighlightPopoverRequest`, `SelectionToolbarRequest`) that SwiftUI presents. Engines register their commands as `ReaderEngineActions` closures on the model.
- Menu commands use `FocusedValue`: the focused reader window publishes `ReaderActions`; the library publishes `LibraryActions`. App-wide commands (Import ⌘O, Search ⌘⇧F) go through `AppSession`.
- Popover anchors are rects in the reader content view's coordinate space (top-left origin), which SwiftUI uses as `.popover(attachmentAnchor: .rect(.rect(...)))`.

## Alternatives considered
- Reader inside the main window's detail column: one document at a time, and the sidebar takes reading width.
- Tabs in one reader window: more AppKit work for little gain in Phase 1.

## Consequences
- Several documents can be open side by side, and search or the browser stays usable while reading.
- Commands that only make sense in a reader are disabled when no reader window is focused.
