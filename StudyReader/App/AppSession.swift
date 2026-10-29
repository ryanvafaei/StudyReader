import Foundation
import Observation

/// The two screens of the sidebar Review section (ADR-0022).
enum ReviewSectionMode: String, Sendable {
    case daily, flashcards
}

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
    /// Keeps the daily review reminder notification in step with the settings (ADR-0022).
    let reminder: ReviewReminderScheduler
    @ObservationIgnored private var dailyReview: ReviewSessionModel?
    @ObservationIgnored private var flashcards: FlashcardsModel?
    /// Which screen the Review section shows (Daily Review or Flashcards). Not persisted across launches.
    var reviewSectionMode: ReviewSectionMode = .daily
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
        // The user's library is decided like export sync (`runsExportSync`). Tests, previews and the in-memory
        // library get a no-op center so they never ask for notification permission.
        let center: any ReminderNotificationCenter = environment.runsExportSync
            ? SystemReminderNotificationCenter()
            : NoopReminderNotificationCenter()
        self.reminder = ReviewReminderScheduler(center: center)
    }

    /// Applies the reminder settings. If permission is denied, turns the setting off so the toggle matches.
    func applyReminderSettings() async {
        let applied = await reminder.apply(
            enabled: settings.reviewReminderEnabled,
            minutes: settings.reviewReminderMinutes
        )
        if !applied && settings.reviewReminderEnabled {
            settings.reviewReminderEnabled = false
        }
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

    /// The Flashcards model, created once and reused, so the filters and the selected card survive a switch to the
    /// daily review or another sidebar section. Not persisted across launches.
    func flashcardsModel() -> FlashcardsModel {
        if let flashcards {
            return flashcards
        }
        let model = FlashcardsModel(environment: environment)
        flashcards = model
        return model
    }
}
