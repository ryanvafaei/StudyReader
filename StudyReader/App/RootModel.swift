import Observation

/// Holds the main window's navigation state.
@MainActor @Observable
final class RootModel {
    var selection: SidebarItem? = .library

    init() {}
}
