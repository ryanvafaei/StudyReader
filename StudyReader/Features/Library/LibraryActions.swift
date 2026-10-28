import SwiftUI

/// Published by the library with `.focusedSceneValue` so menu commands can act on the selection (ADR-0017).
/// The hooks stay nil until their owning task wires them (T50 sets `editMetadata`, T73 sets `exportHighlights`).
/// `exportHighlights` takes a document id for that document's scope, or nil for the sheet's default (All highlights).
struct LibraryActions {
    var selectedDocumentId: String?
    var editMetadata: (@MainActor (String) -> Void)?
    var exportHighlights: (@MainActor (String?) -> Void)?
}

extension FocusedValues {
    @Entry var libraryActions: LibraryActions? = nil
}
