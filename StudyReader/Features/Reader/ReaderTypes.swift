import CoreGraphics
import Foundation

/// The reader's right panel tabs (SPEC F-06 highlights list, F-09 document notes).
enum ReaderPanelTab: String, CaseIterable, Sendable {
    case highlights, notes
}

/// Rect in the reader content view's coordinate space, top-left origin (ADR-0017).
struct HighlightPopoverRequest: Identifiable, Equatable {
    let highlightId: String
    let anchorRect: CGRect
    var focus: PopoverFocus = .none
    var id: String { highlightId }
}

/// Which field the highlight popover focuses when it opens.
enum PopoverFocus: Equatable, Sendable {
    case none, note, tags
}

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
