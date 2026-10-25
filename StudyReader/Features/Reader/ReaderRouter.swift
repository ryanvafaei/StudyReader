import Foundation
import Observation
import SwiftUI

/// Where a reader should show something once it is open (ADR-0017).
enum ReaderLocation: Hashable, Sendable {
    case page(Int)                                // PDF page index, 0-based
    case highlight(String)                        // highlight id
    case searchHit(unitIndex: Int, query: String) // documentText unit (PDF page / Markdown section) + raw query
    case documentNote                             // open the Notes tab
}

/// Opens reader windows and keeps the location each one should show next (ADR-0017).
/// Owned by `AppSession`; the reader tab's `ReaderModel` takes the pending location on load and when it changes.
@MainActor @Observable
final class ReaderRouter {
    static let windowId = "reader"

    /// Pending location per document ID. Taken once by the document's model.
    private(set) var pendingLocations: [String: ReaderLocation] = [:]

    /// Stores `location` for the document, or removes the pending entry when `location` is nil.
    func setPendingLocation(_ location: ReaderLocation?, for documentId: String) {
        pendingLocations[documentId] = location
    }

    /// Returns and removes the pending location for the document.
    func takePendingLocation(for documentId: String) -> ReaderLocation? {
        pendingLocations.removeValue(forKey: documentId)
    }

    /// setPendingLocation, then openWindow(id: windowId, value: documentId). Each document is a reader window
    /// that joins the main window's native tab group (T52, ADR-0017); an equal value reuses the open tab.
    func open(documentId: String, at location: ReaderLocation? = nil, using openWindow: OpenWindowAction) {
        setPendingLocation(location, for: documentId)
        openWindow(id: Self.windowId, value: documentId)
    }
}
