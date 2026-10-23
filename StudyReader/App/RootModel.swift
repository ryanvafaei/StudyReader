import Observation

/// Holds the main window's navigation state and the app's long-lived dependencies.
@MainActor @Observable
final class RootModel {
    let environment: AppEnvironment
    var selection: SidebarItem? = .library

    init(environment: AppEnvironment) {
        self.environment = environment
    }
}
