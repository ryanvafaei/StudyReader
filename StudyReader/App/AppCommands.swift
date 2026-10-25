import SwiftUI

/// Commands the main window publishes for the menu bar. nil when no library window is focused.
struct ImportActions {
    let importFiles: () -> Void
}

extension FocusedValues {
    @Entry var importActions: ImportActions? = nil
}

/// File menu items (SPEC F-02, §5 shortcuts). The import command is disabled until the library is open.
struct AppCommands: Commands {
    @FocusedValue(\.importActions) private var importActions: ImportActions?
    @FocusedValue(\.libraryActions) private var libraryActions: LibraryActions?

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
                if let id = libraryActions?.selectedDocumentId {
                    libraryActions?.editMetadata?(id)
                }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(libraryActions?.selectedDocumentId == nil || libraryActions?.editMetadata == nil)
        }
    }
}
