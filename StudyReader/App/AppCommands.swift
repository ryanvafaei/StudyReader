import SwiftUI

/// Commands the main window publishes for the menu bar. nil when no library window is focused.
struct ImportActions {
    let importFiles: () -> Void
}

extension FocusedValues {
    @Entry var importActions: ImportActions? = nil
}

/// Menu commands (SPEC F-02, F-04, §5 shortcuts). Library commands read `libraryActions`; reader commands read
/// `readerActions` from the focused reader tab (ADR-0017). Reader items are disabled when no reader tab is focused
/// or when the engine doesn't provide the action yet (T53 and T55 provide the PDF and Markdown actions).
struct AppCommands: Commands {
    @FocusedValue(\.importActions) private var importActions: ImportActions?
    @FocusedValue(\.libraryActions) private var libraryActions: LibraryActions?
    @FocusedValue(\.readerActions) private var readerActions: ReaderActions?

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

        CommandGroup(after: .textEditing) {
            Button("Find in Document") {
                readerActions?.model.engineActions.findInDocument?()
            }
            .keyboardShortcut("f")
            .disabled(readerActions?.model.engineActions.findInDocument == nil)
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
            .keyboardShortcut("h", modifiers: [.command, .option])
            .disabled(readerActions == nil)
        }

        CommandMenu("Document") {
            Button("Snapshot") {
                readerActions?.model.engineActions.startSnapshot?()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(readerActions?.model.engineActions.startSnapshot == nil)
        }
    }
}
