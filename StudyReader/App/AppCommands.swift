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

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Import…") {
                importActions?.importFiles()
            }
            .keyboardShortcut("o")
            .disabled(importActions == nil)
        }
    }
}
