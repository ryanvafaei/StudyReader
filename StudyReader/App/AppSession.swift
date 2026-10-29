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
    /// The library's selected document id. Kept here, not in LibraryView, so it survives the search results replacing
    /// the library (BACKLOG B22 1). LibraryView shows it only while the document is listed (`LibraryModel.existingSelection`).
    var librarySelection: String?
    /// The library's filter (category, tag, file type, has highlights). Kept here, not in LibraryView's model, so it
    /// survives the search results replacing the library and a switch to another sidebar section (W2, BACKLOG B22).
    /// Not persisted across launches.
    var libraryFilter = LibraryFilter()

    init(environment: AppEnvironment) {
        self.environment = environment
        self.settings = AppSettings(store: environment.settingsStore)
        self.importCoordinator = ImportCoordinator(importService: environment.importService)
        self.search = SearchModel(environment: environment)
    }
}
