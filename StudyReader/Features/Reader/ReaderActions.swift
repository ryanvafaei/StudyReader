import Observation
import SwiftUI

/// View-only state of one reader tab (not part of ReaderModel).
@MainActor @Observable
final class ReaderWindowState {
    var isMetadataSheetPresented = false
}

/// Published by the focused reader tab with `.focusedSceneValue` (ADR-0017). The menu commands read it, so they are
/// disabled whenever a reader window isn't focused.
struct ReaderActions {
    let model: ReaderModel
    let windowState: ReaderWindowState
}

extension FocusedValues {
    @Entry var readerActions: ReaderActions? = nil
}
