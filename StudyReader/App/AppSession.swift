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
    /// The sidebar badge: today's daily plan size (SPEC F-15).
    let reviewBadge: ReviewBadgeModel
    /// The daily review session, kept so leaving the review section and coming back resumes it (ADR-0022).
    /// Holds no reference back to this session: it keeps `environment` and `settings` only.
    @ObservationIgnored private var dailyReview: ReviewSessionModel?
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
        let settings = AppSettings(store: environment.settingsStore)
        self.environment = environment
        self.settings = settings
        self.importCoordinator = ImportCoordinator(importService: environment.importService)
        self.search = SearchModel(environment: environment)
        self.reviewBadge = ReviewBadgeModel(environment: environment, settings: settings)
    }

    /// The daily review session model, created once and reused. Views read it through here so a session survives
    /// navigation between sidebar sections.
    func dailyReviewModel() -> ReviewSessionModel {
        if let dailyReview {
            return dailyReview
        }
        let model = ReviewSessionModel(session: self)
        dailyReview = model
        return model
    }
}
