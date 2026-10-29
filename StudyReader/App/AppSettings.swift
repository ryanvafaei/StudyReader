import Foundation
import Observation

/// Live mirror of `SettingsStore` (ADR-0015). Every property is read once in `init` and written through in `didSet`.
/// Owned by `AppSession` only, so every window sees the same values.
@MainActor @Observable
final class AppSettings {
    private let store: SettingsStore

    var defaultCategoryId: String {
        didSet { store.defaultCategoryId = defaultCategoryId }
    }

    var autoHighlight: Bool {
        didSet { store.autoHighlight = autoHighlight }
    }

    var currentColor: HighlightColor {
        didSet { store.currentColor = currentColor }
    }

    var invertPDFInDarkMode: Bool {
        didSet { store.invertPDFInDarkMode = invertPDFInDarkMode }
    }

    var reviewDailyLimit: Int {
        didSet { store.reviewDailyLimit = reviewDailyLimit }
    }

    var reviewNewPerDay: Int {
        didSet { store.reviewNewPerDay = reviewNewPerDay }
    }

    var showFourRatingButtons: Bool {
        didSet { store.showFourRatingButtons = showFourRatingButtons }
    }

    var reviewReminderEnabled: Bool {
        didSet { store.reviewReminderEnabled = reviewReminderEnabled }
    }

    /// Minutes after local midnight.
    var reviewReminderMinutes: Int {
        didSet { store.reviewReminderMinutes = reviewReminderMinutes }
    }

    var dailyLimits: DailyLimits {
        DailyLimits(dailyLimit: reviewDailyLimit, newPerDay: reviewNewPerDay)
    }

    /// Index = `HighlightColor.rawValue` (5 entries).
    private(set) var colorLabels: [String]

    init(store: SettingsStore) {
        self.store = store
        self.defaultCategoryId = store.defaultCategoryId
        self.autoHighlight = store.autoHighlight
        self.currentColor = store.currentColor
        self.invertPDFInDarkMode = store.invertPDFInDarkMode
        self.reviewDailyLimit = store.reviewDailyLimit
        self.reviewNewPerDay = store.reviewNewPerDay
        self.showFourRatingButtons = store.showFourRatingButtons
        self.reviewReminderEnabled = store.reviewReminderEnabled
        self.reviewReminderMinutes = store.reviewReminderMinutes
        self.colorLabels = HighlightColor.allCases.map { store.colorLabel(for: $0) }
    }

    func label(for color: HighlightColor) -> String {
        colorLabels[color.rawValue]
    }

    /// Writes through to the store (an empty label restores the default), then re-reads the label.
    func setLabel(_ label: String, for color: HighlightColor) {
        store.setColorLabel(label, for: color)
        colorLabels[color.rawValue] = store.colorLabel(for: color)
    }
}
