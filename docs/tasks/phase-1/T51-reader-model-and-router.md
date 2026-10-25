# T51: ReaderModel and ReaderRouter

- **Phase:** 1 (E1.2/E1.3/E1.4 shared reader logic: F-04 position, F-06 events)
- **Agent:** ui-builder
- **Depends on:** T38, T45
- **ADRs:** docs/decisions/0017-reader-windows-and-commands.md (read in full), docs/decisions/0015-settings-and-injected-sleep.md (Debouncer), docs/decisions/0013-schema-migration-policy-v2.md (column-limited saves)
- **Visual check needed:** no (T52 shows the tabs)

## Goal
The per-tab model every reader engine talks to (ADR-0017; each document is a native window tab in the main window's tab group, which T52 sets up): loads the document, saves and restores reading position (F-04, debounced), records last opened, exposes the document's live highlights, creates highlights through `HighlightService`, carries popover and selection-toolbar requests for SwiftUI, and receives navigation requests from `ReaderRouter`. Pure logic, fully unit-tested; the engines (T53, T55, T59, T60) and chrome (T52, T62, T63) build on these exact names.

## Files to touch
- `StudyReader/Features/Reader/ReaderRouter.swift` (new)
- `StudyReader/Features/Reader/ReaderModel.swift` (new)
- `StudyReader/Features/Reader/ReaderTypes.swift` (new: requests, engine actions, panel enum)
- `StudyReader/App/AppSession.swift` (modify: `let router = ReaderRouter()`)
- `StudyReaderTests/ReaderTests/ReadingPositionTests.swift`, `StudyReaderTests/ReaderTests/ReaderModelTests.swift`, `StudyReaderTests/ReaderTests/ReaderRouterTests.swift` (new)

## Interfaces to produce
```swift
// ReaderRouter.swift
enum ReaderLocation: Hashable, Sendable {
    case page(Int)                                // PDF page index, 0-based
    case highlight(String)                        // highlight id
    case searchHit(unitIndex: Int, query: String) // documentText unit (PDF page / Markdown section) + raw query
    case documentNote                             // open the Notes tab
}

@MainActor @Observable
final class ReaderRouter {
    static let windowId = "reader"
    private(set) var pendingLocations: [String: ReaderLocation] = [:]
    func setPendingLocation(_ location: ReaderLocation?, for documentId: String)   // nil removes
    func takePendingLocation(for documentId: String) -> ReaderLocation?            // returns and removes
    /// setPendingLocation, then openWindow(id: windowId, value: documentId). Each document is a reader window
    /// that joins the main window's native tab group (T52, ADR-0017); an equal value reuses the open tab.
    func open(documentId: String, at location: ReaderLocation? = nil, using openWindow: OpenWindowAction)
}

// ReaderTypes.swift
enum ReaderPanelTab: String, CaseIterable, Sendable { case highlights, notes }

/// Rect in the reader content view's coordinate space, top-left origin (ADR-0017).
struct HighlightPopoverRequest: Identifiable, Equatable {
    let highlightId: String
    let anchorRect: CGRect
    var focus: PopoverFocus = .none
    var id: String { highlightId }
}
enum PopoverFocus: Equatable, Sendable { case none, note, tags }

/// Shown when auto-highlight is off (SPEC F-06): the selection waiting for a color.
struct SelectionToolbarRequest: Identifiable, Equatable {
    let id: UUID
    let pending: NewTextHighlight      // color = settings.currentColor until the user picks one
    let anchorRect: CGRect
}

/// Commands an engine registers on the model (all optional; nil = command disabled).
struct ReaderEngineActions {
    var zoomIn: (@MainActor () -> Void)?
    var zoomOut: (@MainActor () -> Void)?
    var actualSize: (@MainActor () -> Void)?
    var fitWidth: (@MainActor () -> Void)?
    var toggleSinglePage: (@MainActor () -> Void)?
    var toggleThumbnails: (@MainActor () -> Void)?
    var startSnapshot: (@MainActor () -> Void)?
    var findInDocument: (@MainActor () -> Void)?
    var currentPageIndex: (@MainActor () -> Int?)?
    var copySelection: (@MainActor () -> Void)?
}

// ReaderModel.swift
@MainActor @Observable
final class ReaderModel {
    enum LoadState: Equatable { case loading, ready, failed(String) }
    static let positionSaveDelay: Duration = .seconds(1)

    let documentId: String
    let session: AppSession
    private(set) var state: LoadState = .loading
    private(set) var document: LibraryDocument?
    private(set) var fileURL: URL?
    /// Live, ordered like HighlightRepository.fetchForDocument.
    private(set) var highlights: [Highlight] = []
    var isRightPanelVisible = false
    var rightPanelTab: ReaderPanelTab = .highlights
    var popoverRequest: HighlightPopoverRequest?
    var selectionToolbar: SelectionToolbarRequest?
    /// Engines apply it when non-nil and then call consumeLocation().
    private(set) var pendingLocation: ReaderLocation?
    var engineActions = ReaderEngineActions()
    private(set) var transientMessage: String?      // short error text, e.g. a failed highlight save

    init(documentId: String, session: AppSession)

    /// Fetches the document; resolves fileURL with fileStore.url(forRelativePath: storedPath) and checks the file
    /// exists (else .failed("The document file is missing.")); markOpened(at: now()); takes the router's pending
    /// location; state = .ready. Unknown id → .failed("This document is no longer in the library.").
    func load() async
    /// Observes highlightRepository.observeForDocument(documentId) until the calling task is cancelled.
    func observeHighlights() async
    /// Takes the router's pending location for this document, if any, and calls navigate(to:).
    /// The window calls it from .onChange(of: session.router.pendingLocations[documentId]).
    func receiveRouterLocation()
    func navigate(to location: ReaderLocation)       // sets pendingLocation; .documentNote also opens the Notes tab
    func consumeLocation()

    // Reading position (F-04). Saves are debounced (positionSaveDelay, environment.sleeper).
    var initialPDFPosition: PDFPosition? { get }      // document?.pdfPosition at load time
    var initialTextOffset: Int? { get }               // document?.textPosition at load time
    /// progress = Double(position.pageIndex + 1) / Double(max(pageCount, 1)), clamped 0...1.
    func pdfPositionChanged(_ position: PDFPosition, pageCount: Int)
    /// progress = Double(offset) / Double(max(textLength, 1)), clamped 0...1.
    func textPositionChanged(offset: Int, textLength: Int)
    /// Saves the latest unsaved position now. The window calls it on close.
    func flushPosition() async

    // Highlights (F-06)
    /// highlightService.createText(new, isAuto:). Errors → transientMessage. Returns the highlight or nil.
    @discardableResult func createHighlight(_ new: NewTextHighlight, isAuto: Bool) async -> Highlight?
    func undoLastAutoHighlight() async                // highlightService.undoLastAutoHighlight()
    func showPopover(highlightId: String, anchorRect: CGRect, focus: PopoverFocus = .none)
    /// Auto-highlight on → createHighlight(new with settings.currentColor, isAuto: true).
    /// Off → selectionToolbar = SelectionToolbarRequest(id: UUID(), pending: new, anchorRect:).
    func selectionFinished(_ new: NewTextHighlight, anchorRect: CGRect) async
    /// Selection toolbar color dot: create with that color (isAuto false), close the toolbar.
    func applyToolbarColor(_ color: HighlightColor) async
    /// Toolbar Note / Tag: create in the current color, then showPopover with focus .note / .tags.
    func applyToolbarNoteOrTag(focus: PopoverFocus) async
}
```
- Saves call `documentRepository.updatePDFPosition` / `updateTextPosition` (column-limited, T34). Never save on the main thread synchronously; the debouncer's action is `@Sendable` and captures only Sendable values (ids, the position, the repository).
- `selectionFinished` with a keyboard color (1–5/H) is handled by engines calling `createHighlight` directly with that color and `isAuto: false`.
- `undoLastAutoHighlight()` is what the engines register with `UndoManager` (T59, T60).

## Tests (`@MainActor`; `AppEnvironment` built with `AppEnvironment(fileStore:database:now:settingsStore:sleeper:)` over `inMemory()` parts, `FixedNow(TestData.referenceDate)`, `TestSettings.make()`, `ImmediateSleeper`; remove folders/suites in `defer`)
`ReadingPositionTests`:
- `restoresPosition` (SPEC F-04 AC1): document with a real file (copy any `PDFFixtureBuilder` PDF to `originalFileURL`); model A `load()`, `pdfPositionChanged(PDFPosition(pageIndex: 3, offsetY: 412.5), pageCount: 10)`, `flushPosition()`; model B `load()` → `initialPDFPosition == PDFPosition(pageIndex: 3, offsetY: 412.5)` and the row's progress is 0.4.
- `restoresTextOffset`: same with `textPositionChanged(offset: 250, textLength: 1000)` → `initialTextOffset == 250`, progress 0.25.
- `marksLastOpened`: after `load()`, `lastOpenedAt == TestData.referenceDate`.
- `onlyLatestPositionIsSaved`: with a `ManualSleeper` environment, three changes then `waitForSleepers(3)`, `resumeAll()`; poll until the row shows the third position.
`ReaderModelTests`:
- `missingDocumentFails`, `missingFileFails` (row exists, file deleted).
- `autoHighlightCreatesImmediately`: `settings.autoHighlight = true`, `currentColor = .blue`; `selectionFinished(new, anchorRect:)` → one highlight with `.blue`; `selectionToolbar == nil`; `undoLastAutoHighlight()` removes it.
- `toolbarWhenAutoHighlightOff`: `autoHighlight = false` → no highlight, `selectionToolbar?.pending == new` (with current color); `applyToolbarColor(.pink)` → highlight with `.pink`, toolbar nil; `applyToolbarNoteOrTag(focus: .note)` → highlight created and `popoverRequest?.focus == .note`.
- `highlightsAreLive`: run `observeHighlights()` in a Task; insert through the service; poll until `highlights.count == 1`.
- `documentNoteLocationOpensNotesTab`: `navigate(to: .documentNote)` → `isRightPanelVisible`, `rightPanelTab == .notes`, `pendingLocation == .documentNote`; `consumeLocation()` → nil.
`ReaderRouterTests`:
- `pendingLocationIsTakenOnce`; `loadTakesPendingLocation` (set `.page(2)` before `load()` → `pendingLocation == .page(2)` and the router no longer has it).

## Acceptance criteria
1. Opening a document restores the last page and offset. → test `ReadingPositionTests/restoresPosition` (SPEC F-04 AC1); also `restoresTextOffset`, `marksLastOpened`, `onlyLatestPositionIsSaved`
2. Auto-highlight on creates at once and can be undone; off shows the toolbar request. → tests `ReaderModelTests/autoHighlightCreatesImmediately`, `toolbarWhenAutoHighlightOff`
3. Load failures, live highlights, navigation and routing behave as specified. → tests `missingDocumentFails`, `missingFileFails`, `highlightsAreLive`, `documentNoteLocationOpensNotesTab`, `ReaderRouterTests/*`

## Out of scope
- Any view or AppKit code (T52, T53, T55), engine geometry (T56, T57).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
- 2026-10-25, Sonnet (code-reviewer, effort medium): APPROVED. 353 tests pass, 0 warnings. No visual check (no views). Minor: a pending router location stays if load() fails; onlyLatestPositionIsSaved checks only the final position.
