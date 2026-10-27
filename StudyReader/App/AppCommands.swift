import SwiftUI

/// Commands the main window publishes for the menu bar. nil when no library window is focused.
struct ImportActions {
    let importFiles: () -> Void
}

extension FocusedValues {
    @Entry var importActions: ImportActions? = nil
    /// The session of the focused library window, so the search commands can reach the search field.
    @Entry var searchSession: AppSession? = nil
}

/// Menu commands (SPEC F-02, F-04, §5 shortcuts). Library commands read `libraryActions`; reader commands read
/// `readerActions` from the focused reader tab (ADR-0017). Reader items are disabled when no reader tab is focused
/// or when the engine doesn't provide the action yet (T53 and T55 provide the PDF and Markdown actions).
struct AppCommands: Commands {
    @FocusedValue(\.importActions) private var importActions: ImportActions?
    @FocusedValue(\.libraryActions) private var libraryActions: LibraryActions?
    @FocusedValue(\.readerActions) private var readerActions: ReaderActions?
    @FocusedValue(\.searchSession) private var searchSession: AppSession?
    @Environment(\.openWindow) private var openWindow

    /// The session whose library search a command can focus: the library window's, or the focused reader's.
    private var activeSession: AppSession? {
        searchSession ?? readerActions?.model.session
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Import…") {
                importActions?.importFiles()
            }
            .keyboardShortcut("o")
            .disabled(importActions == nil)
        }

        CommandGroup(after: .newItem) {
            Button("Edit Metadata…") {
                if let readerActions {
                    readerActions.windowState.isMetadataSheetPresented = true
                } else if let id = libraryActions?.selectedDocumentId {
                    libraryActions?.editMetadata?(id)
                }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(readerActions == nil && (libraryActions?.selectedDocumentId == nil || libraryActions?.editMetadata == nil))
        }

        // Replaces the system Undo/Redo: a read-only reader (TextKit 2 view, PDFView) reports them disabled and never
        // titles them, but the auto-highlight registers one undo action ("Undo Highlight"). Anything else (a text field
        // in a sheet or the library) goes down the responder chain as before.
        CommandGroup(replacing: .undoRedo) {
            Button {
                performUndo()
            } label: {
                Text(readerActions?.model.canUndoHighlight == true ? String(localized: "Undo Highlight") : String(localized: "Undo"))
            }
            .keyboardShortcut("z")

            Button {
                NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
            } label: {
                Text("Redo")
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        CommandGroup(after: .textEditing) {
            // One ⌘F: finds in the focused reader (disabled until its engine provides it); with the library window in
            // front it puts the keyboard in the library search field.
            Button {
                if let find = readerActions?.model.engineActions.findInDocument {
                    find()
                } else if readerActions == nil {
                    focusLibrarySearch()
                }
            } label: {
                Text(readerActions == nil ? LocalizedStringKey("Find in Library") : LocalizedStringKey("Find in Document"))
            }
            .keyboardShortcut("f")
            .disabled(readerActions == nil ? searchSession == nil : readerActions?.model.engineActions.findInDocument == nil)

            Button("Search Library") {
                focusLibrarySearch()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(activeSession == nil)
        }

        CommandGroup(after: .toolbar) {
            Button("Zoom In") {
                readerActions?.model.engineActions.zoomIn?()
            }
            .keyboardShortcut("=")
            .disabled(readerActions?.model.engineActions.zoomIn == nil)

            Button("Zoom Out") {
                readerActions?.model.engineActions.zoomOut?()
            }
            .keyboardShortcut("-")
            .disabled(readerActions?.model.engineActions.zoomOut == nil)

            Button("Actual Size") {
                readerActions?.model.engineActions.actualSize?()
            }
            .keyboardShortcut("0")
            .disabled(readerActions?.model.engineActions.actualSize == nil)

            Button("Fit Width") {
                readerActions?.model.engineActions.fitWidth?()
            }
            .keyboardShortcut("9")
            .disabled(readerActions?.model.engineActions.fitWidth == nil)

            Divider()

            Button("Single Page") {
                readerActions?.model.engineActions.toggleSinglePage?()
            }
            .disabled(readerActions?.model.engineActions.toggleSinglePage == nil)

            Button("Show Thumbnails") {
                readerActions?.model.engineActions.toggleThumbnails?()
            }
            .disabled(readerActions?.model.engineActions.toggleThumbnails == nil)
        }

        CommandGroup(after: .sidebar) {
            Button("Highlights Panel") {
                readerActions?.model.toggleRightPanel(tab: .highlights)
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(readerActions?.model.isDocumentAvailable != true)
        }

        CommandMenu("Document") {
            Button("Snapshot") {
                readerActions?.model.engineActions.startSnapshot?()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(readerActions?.model.engineActions.startSnapshot == nil)
        }
    }

    /// Brings the library window forward and puts the keyboard in its search field.
    @MainActor
    private func focusLibrarySearch() {
        guard let session = activeSession else { return }
        openWindow(id: "main")
        session.isSearchFocused = false
        Task { @MainActor in
            await Task.yield()
            session.isSearchFocused = true
        }
    }

    /// Removes the frontmost reader's last auto-highlight. Normally it runs the first responder's (or the window's)
    /// undo manager, the same path as the responder chain; the action registered there only calls
    /// `ReaderModel.undoLastAutoHighlight()` on the tab that registered it. When that manager has nothing to undo, it
    /// calls the model directly, but only while the reader view itself has the keyboard (see `isReaderUndoContext`).
    /// Anywhere else (a sheet, a popover field, the library) Undo goes down the responder chain, so ⌘Z in an empty
    /// field never deletes a highlight. The model removes only the highlight it created itself, so ⌘Z never deletes
    /// another tab's.
    @MainActor
    private func performUndo() {
        guard let model = readerActions?.model, model.canUndoHighlight else {
            NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
            return
        }
        let window = NSApp.keyWindow
        if let manager = window?.firstResponder?.undoManager ?? window?.undoManager, manager.canUndo {
            manager.undo()
        } else if Self.isReaderUndoContext(window) {
            Task { await model.undoLastAutoHighlight() }
        } else {
            NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
        }
    }

    /// True when `window` is a reader's own window (not a sheet, popover or other panel) and its first responder is
    /// not an editable text view or field editor, i.e. it is the reader view, its scroll view or nothing in particular.
    @MainActor
    static func isReaderUndoContext(_ window: NSWindow?) -> Bool {
        guard let window, window.sheetParent == nil, window.canBecomeMain else { return false }
        if let text = window.firstResponder as? NSTextView, text.isFieldEditor || text.isEditable {
            return false
        }
        return true
    }
}
