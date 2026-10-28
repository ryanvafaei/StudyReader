import CoreGraphics
import Foundation
import Observation

/// The per-tab model every reader engine talks to (ADR-0017). Loads one document, saves and restores its reading
/// position (SPEC F-04, debounced per ADR-0015), records last opened, exposes live highlights (F-06), creates
/// highlights through `HighlightService`, and receives navigation from `ReaderRouter`.
@MainActor @Observable
final class ReaderModel: PendingWriteFlushing {
    enum LoadState: Equatable {
        case loading, ready, failed(String)
    }

    static let positionSaveDelay: Duration = .seconds(1)

    let documentId: String
    let session: AppSession

    private(set) var state: LoadState = .loading
    private(set) var document: LibraryDocument?
    /// Shown as the tab's subtitle (ADR-0017). Nil when the category can't be read.
    private(set) var categoryName: String?
    private(set) var fileURL: URL?
    /// Live, ordered like HighlightRepository.fetchForDocument.
    private(set) var highlights: [Highlight] = []
    /// True after the first emission of `observeHighlights()`; until then an empty `highlights` means "not loaded".
    private(set) var hasLoadedHighlights = false
    var isRightPanelVisible = false
    var rightPanelTab: ReaderPanelTab = .highlights
    var popoverRequest: HighlightPopoverRequest?
    var selectionToolbar: SelectionToolbarRequest?
    /// Engines apply it when non-nil and then call consumeLocation().
    private(set) var pendingLocation: ReaderLocation?
    var engineActions = ReaderEngineActions()
    private(set) var transientMessage: String?
    /// The auto-highlight the service remembers for ⌘Z, as created. Cleared when it is undone, when any other
    /// highlight is created or fails to be, when the live highlights show it deleted or recoloured (the service
    /// forgets it on both, whichever code path made the change), when the live row has a note or edited text, and
    /// when the popover opens on it. Undo only removes a bare highlight (the service checks again at the delete).
    private var autoHighlightMark: AutoHighlightMark?

    private struct AutoHighlightMark {
        let id: String
        let color: HighlightColor
        /// Set once the live highlights have listed it, so an older snapshot can't be read as a deletion.
        var seen = false
    }

    /// True while Edit > Undo Highlight can remove the last auto-highlight; the menu reads it for its title and
    /// enabled state.
    var canUndoHighlight: Bool { autoHighlightMark != nil }

    private let positionDebouncer: Debouncer
    /// Serializes schedule calls so the debouncer sees position changes in the order they happened.
    private var saveChain: Task<Void, Never>?
    private var initialPosition: PDFPosition?
    private var initialOffset: Int?

    init(documentId: String, session: AppSession) {
        self.documentId = documentId
        self.session = session
        self.positionDebouncer = Debouncer(delay: Self.positionSaveDelay, sleeper: session.environment.sleeper)
        session.environment.pendingWrites.register(self)
    }

    func flushPendingWrites() async {
        await flushPosition()
    }

    // MARK: - Loading

    /// Fetches the document, resolves and checks its file, records the open, takes the router's pending location.
    func load() async {
        let environment = session.environment
        do {
            guard let loaded = try await environment.documentRepository.fetch(id: documentId) else {
                fail(String(localized: "This document is no longer in the library."))
                return
            }
            document = loaded
            categoryName = (try? await environment.categoryRepository.fetch(id: loaded.categoryId))?.name
            guard let url = environment.fileStore.url(forRelativePath: loaded.storedPath),
                  FileManager.default.fileExists(atPath: url.path) else {
                fail(String(localized: "The document file is missing."))
                return
            }
            fileURL = url
            initialPosition = loaded.pdfPosition
            initialOffset = loaded.textPosition
            try await environment.documentRepository.markOpened(id: documentId, at: environment.now())
            if let location = session.router.takePendingLocation(for: documentId) {
                navigate(to: location)
            }
            state = .ready
        } catch {
            Log.database.error("Loading the document failed.")
            fail(String(localized: "The document couldn't be opened."))
        }
    }

    /// True only when `state == .ready`. The tab shows the colour menu, the inspector toggle and the inspector only
    /// then, and View > Highlights Panel is disabled otherwise.
    var isDocumentAvailable: Bool { state == .ready }

    /// An engine couldn't show the document (`PDFDocument(url:)` returned nil; T55 uses it for an unreadable Markdown
    /// file). Marks the document unavailable and closes the right panel.
    func engineFailed(_ message: String) {
        fail(message)
    }

    private func fail(_ message: String) {
        state = .failed(message)
        isRightPanelVisible = false
    }

    /// Keeps `document` (title, author, categoryId) and `categoryName` in step with metadata edits, category renames
    /// and category deletions (a deleted category's documents move to Other). Runs until the calling task is
    /// cancelled. Errors are logged and end the observation; they don't change `state`.
    func observeMetadata() async {
        do {
            for try await items in session.environment.documentRepository.observeItems() {
                guard let item = items.first(where: { $0.id == documentId }) else { continue }
                applyMetadata(item)
            }
        } catch {
            Log.database.error("Observing the document metadata failed.")
        }
    }

    /// Applies one observed item. Updates `categoryName` when it differs. Updates `document` only when title, author
    /// or categoryId differ, so position and progress saves don't re-render the tab. Does nothing to `document`
    /// while it is nil.
    func applyMetadata(_ item: LibraryItem) {
        if categoryName != item.categoryName {
            categoryName = item.categoryName
        }
        guard var current = document else { return }
        let observed = item.document
        guard current.title != observed.title
            || current.author != observed.author
            || current.categoryId != observed.categoryId else { return }
        current.title = observed.title
        current.author = observed.author
        current.categoryId = observed.categoryId
        document = current
    }

    /// Observes this document's highlights until the calling task is cancelled.
    func observeHighlights() async {
        do {
            for try await rows in session.environment.highlightRepository.observeForDocument(documentId) {
                highlights = rows
                hasLoadedHighlights = true
                reconcileAutoHighlightMark()
            }
        } catch {
            Log.database.error("Observing highlights failed.")
            transientMessage = String(localized: "Highlights couldn't be loaded.")
        }
    }

    /// Drops the undo mark once the live row is gone, has another color, or has a note or edited text. Recolouring
    /// and deleting go through the service from the popover and the panel, and notes through `NoteEditorModel`,
    /// which the model doesn't see, so it reads the result here.
    private func reconcileAutoHighlightMark() {
        guard var mark = autoHighlightMark else { return }
        if let row = highlights.first(where: { $0.id == mark.id }) {
            let annotated = row.editedText != nil
                || !row.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if row.color == mark.color && !annotated {
                mark.seen = true
                autoHighlightMark = mark
            } else {
                autoHighlightMark = nil
            }
        } else if mark.seen {
            autoHighlightMark = nil
        }
    }

    // MARK: - Navigation

    /// Applies a location the router queued for this document while the tab was open.
    func receiveRouterLocation() {
        if let location = session.router.takePendingLocation(for: documentId) {
            navigate(to: location)
        }
    }

    func navigate(to location: ReaderLocation) {
        if case .documentNote = location {
            isRightPanelVisible = true
            rightPanelTab = .notes
        }
        pendingLocation = location
    }

    func consumeLocation() {
        pendingLocation = nil
    }

    // MARK: - Reading position (F-04)

    /// The PDF position stored when the document loaded.
    var initialPDFPosition: PDFPosition? { initialPosition }

    /// The text offset stored when the document loaded.
    var initialTextOffset: Int? { initialOffset }

    func pdfPositionChanged(_ position: PDFPosition, pageCount: Int) {
        let progress = Self.clamp(Double(position.pageIndex + 1) / Double(max(pageCount, 1)))
        let repository = session.environment.documentRepository
        let id = documentId
        scheduleSave {
            do {
                try await repository.updatePDFPosition(id: id, position: position, progress: progress)
            } catch {
                Log.database.error("Saving the PDF position failed.")
            }
        }
    }

    func textPositionChanged(offset: Int, textLength: Int) {
        let progress = Self.clamp(Double(offset) / Double(max(textLength, 1)))
        let repository = session.environment.documentRepository
        let id = documentId
        scheduleSave {
            do {
                try await repository.updateTextPosition(id: id, offset: offset, progress: progress)
            } catch {
                Log.database.error("Saving the text position failed.")
            }
        }
    }

    /// Saves the latest unsaved position now. The window calls it on close.
    func flushPosition() async {
        await saveChain?.value
        await positionDebouncer.flush()
    }

    private func scheduleSave(_ action: @escaping @Sendable () async -> Void) {
        let previous = saveChain
        let debouncer = positionDebouncer
        saveChain = Task {
            await previous?.value
            await debouncer.schedule(action)
        }
    }

    // MARK: - Highlights (F-06)

    @discardableResult
    func createHighlight(_ new: NewTextHighlight, isAuto: Bool) async -> Highlight? {
        do {
            let highlight = try await session.environment.highlightService.createText(new, isAuto: isAuto)
            transientMessage = nil
            if isAuto {
                rememberAutoHighlight(highlight)
            } else {
                autoHighlightMark = nil
            }
            return highlight
        } catch {
            autoHighlightMark = nil
            transientMessage = Self.failureMessage(for: error)
            return nil
        }
    }

    /// Marks `highlight` as the auto-highlight ⌘Z may undo. The snapshot listing it can reach the main actor before
    /// `createHighlight` resumes, so the mark starts as seen when the live highlights already list the row; otherwise
    /// a later deletion would never clear it.
    func rememberAutoHighlight(_ highlight: Highlight) {
        autoHighlightMark = AutoHighlightMark(
            id: highlight.id,
            color: highlight.color,
            seen: highlights.contains { $0.id == highlight.id }
        )
        reconcileAutoHighlightMark()
    }

    /// Stores a rendered snapshot as an image highlight (F-08). On failure the banner shows why.
    @discardableResult
    func createSnapshot(_ new: NewImageHighlight) async -> Highlight? {
        do {
            let highlight = try await session.environment.highlightService.createImage(new)
            transientMessage = nil
            autoHighlightMark = nil
            return highlight
        } catch {
            autoHighlightMark = nil
            transientMessage = Self.failureMessage(for: error)
            return nil
        }
    }

    /// Rendering the snapshot failed (the file couldn't be opened or the page rendered).
    func snapshotRenderFailed() {
        transientMessage = String(localized: "The snapshot couldn't be captured.")
    }

    /// Removes the auto-highlight this model created, if the service still remembers it. Does nothing when this model
    /// has none, and never touches another tab's highlight.
    func undoLastAutoHighlight() async {
        guard let mark = autoHighlightMark else { return }
        do {
            _ = try await session.environment.highlightService.undoAutoHighlight(id: mark.id)
            autoHighlightMark = nil
            transientMessage = nil
        } catch {
            transientMessage = Self.failureMessage(for: error)
        }
    }

    /// Shows or hides the right panel on `tab`: the toolbar toggle and ⌥⌘I (View > Highlights Panel) both use it.
    /// Does nothing while the document isn't available (loading or failed).
    func toggleRightPanel(tab: ReaderPanelTab) {
        guard isDocumentAvailable else { return }
        rightPanelTab = tab
        isRightPanelVisible.toggle()
    }

    /// Clears the banner once it has been shown for a while (the view times it).
    func clearTransientMessage() {
        transientMessage = nil
    }

    /// Opening the popover on the auto-highlight ends its undo window: notes and tags are typed there.
    func showPopover(highlightId: String, anchorRect: CGRect, focus: PopoverFocus = .none) {
        if highlightId == autoHighlightMark?.id {
            autoHighlightMark = nil
        }
        popoverRequest = HighlightPopoverRequest(highlightId: highlightId, anchorRect: anchorRect, focus: focus)
    }

    /// Auto-highlight on creates at once in the current color; off shows the selection toolbar. Returns the created
    /// highlight, nil when the toolbar is shown or creation failed.
    @discardableResult
    func selectionFinished(_ new: NewTextHighlight, anchorRect: CGRect) async -> Highlight? {
        var colored = new
        colored.color = session.settings.currentColor
        if session.settings.autoHighlight {
            selectionToolbar = nil
            return await createHighlight(colored, isAuto: true)
        }
        selectionToolbar = SelectionToolbarRequest(id: UUID(), pending: colored, anchorRect: anchorRect)
        return nil
    }

    /// Toolbar color dot: create with that color and close the toolbar.
    func applyToolbarColor(_ color: HighlightColor) async {
        guard var pending = selectionToolbar?.pending else { return }
        selectionToolbar = nil
        pending.color = color
        await createHighlight(pending, isAuto: false)
    }

    /// Toolbar Note or Tag: create in the current color, then open the popover focused on that field.
    func applyToolbarNoteOrTag(focus: PopoverFocus) async {
        guard let request = selectionToolbar else { return }
        selectionToolbar = nil
        if let highlight = await createHighlight(request.pending, isAuto: false) {
            showPopover(highlightId: highlight.id, anchorRect: request.anchorRect, focus: focus)
        }
    }

    // MARK: - Helpers

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    /// User-facing text for a failed save; never the raw error description.
    static func failureMessage(for error: Error) -> String {
        if let serviceError = error as? HighlightServiceError {
            return serviceError.errorDescription ?? String(localized: "The highlight couldn't be saved.")
        }
        return String(localized: "The highlight couldn't be saved.")
    }
}
