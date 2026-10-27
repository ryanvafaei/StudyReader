import Foundation
import Observation

/// Shared state for every window of this app run. Created on the main actor when the library is ready.
@MainActor @Observable
final class AppSession {
    let environment: AppEnvironment
    let settings: AppSettings
    let importCoordinator: ImportCoordinator
    let router = ReaderRouter()
    let search: SearchModel
    /// True while the library search field has keyboard focus (bound to `.searchFocused`).
    var isSearchFocused = false

    init(environment: AppEnvironment) {
        self.environment = environment
        self.settings = AppSettings(store: environment.settingsStore)
        self.importCoordinator = ImportCoordinator(importService: environment.importService)
        self.search = SearchModel(environment: environment)
    }
}
