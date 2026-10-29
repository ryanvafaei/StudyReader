import Foundation

enum LibraryLayout: String, Sendable, CaseIterable { case grid, list }
enum LibrarySort: String, Sendable, CaseIterable { case dateAdded, lastOpened, title, author }

/// Typed per-Mac preferences over one UserDefaults (ADR-0015). Keys are "settings.<property>".
/// The only code that reads or writes these keys.
///
/// UserDefaults is not Sendable under Swift 6, so the store keeps the suite name and resolves
/// the defaults object on each access.
struct SettingsStore: Sendable {
    /// nil for `standard()`. Set for suite-backed stores (tests and the in-memory environment).
    let suiteName: String?

    /// `nil` selects `UserDefaults.standard`. Suite names are internal constants, never user input.
    init(suiteName: String?) {
        self.suiteName = suiteName
    }

    /// The per-Mac defaults. Only the live app uses `UserDefaults.standard`.
    var defaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    static func standard() -> SettingsStore {
        SettingsStore(suiteName: nil)
    }

    static let ephemeralSuiteName = "com.ryanvafaei.StudyReader.Ephemeral"

    /// Suite used by `AppEnvironment.inMemory()` and the default initializer argument. Never `UserDefaults.standard`.
    static func ephemeral() -> SettingsStore {
        SettingsStore(suiteName: ephemeralSuiteName)
    }

    /// Removes everything stored in the ephemeral suite, so the next launch starts with default settings.
    static func resetEphemeral() {
        UserDefaults.standard.removePersistentDomain(forName: ephemeralSuiteName)
    }

    private enum Key {
        static let defaultCategoryId = "settings.defaultCategoryId"
        static let autoHighlight = "settings.autoHighlight"
        static let currentColor = "settings.currentColor"
        static let invertPDFInDarkMode = "settings.invertPDFInDarkMode"
        static let legacyGoogleExportFolderId = "settings.googleExportFolderId"
        static let googleAppFolderIds = "settings.googleAppFolderIds"
        static let libraryLayout = "settings.libraryLayout"
        static let librarySort = "settings.librarySort"
        static let passiveCardBackfillDone = "settings.passiveCardBackfillDone"
        static let reviewDailyLimit = "settings.reviewDailyLimit"
        static let reviewNewPerDay = "settings.reviewNewPerDay"
        static let showFourRatingButtons = "settings.showFourRatingButtons"
        static let reviewReminderEnabled = "settings.reviewReminderEnabled"
        static let reviewReminderMinutes = "settings.reviewReminderMinutes"

        static func colorLabel(_ color: HighlightColor) -> String {
            "settings.colorLabel.\(color.rawValue)"
        }
    }

    var defaultCategoryId: String {
        get { defaults.string(forKey: Key.defaultCategoryId) ?? BuiltinCategory.lectureSlides.id }
        nonmutating set { defaults.set(newValue, forKey: Key.defaultCategoryId) }
    }

    var autoHighlight: Bool {
        get { defaults.object(forKey: Key.autoHighlight) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.autoHighlight) }
    }

    var currentColor: HighlightColor {
        get {
            (defaults.object(forKey: Key.currentColor) as? Int).flatMap(HighlightColor.init(rawValue:)) ?? .yellow
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.currentColor) }
    }

    var invertPDFInDarkMode: Bool {
        get { defaults.object(forKey: Key.invertPDFInDarkMode) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.invertPDFInDarkMode) }
    }

    /// A pasted folder ID saved by an older build. Only `ExportTargetsModel.consumeLegacyFolderNotice()` reads it.
    /// Setting nil removes the key.
    var legacyGoogleExportFolderId: String? {
        get { defaults.string(forKey: Key.legacyGoogleExportFolderId) }
        nonmutating set {
            if let newValue {
                defaults.set(newValue, forKey: Key.legacyGoogleExportFolderId)
            } else {
                defaults.removeObject(forKey: Key.legacyGoogleExportFolderId)
            }
        }
    }

    var libraryLayout: LibraryLayout {
        get { defaults.string(forKey: Key.libraryLayout).flatMap(LibraryLayout.init(rawValue:)) ?? .grid }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.libraryLayout) }
    }

    var librarySort: LibrarySort {
        get { defaults.string(forKey: Key.librarySort).flatMap(LibrarySort.init(rawValue:)) ?? .dateAdded }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.librarySort) }
    }

    /// true once `LibraryMaintenance.backfillPassiveCardsOnce` has run on this Mac (T129, ADR-0015).
    var passiveCardBackfillDone: Bool {
        get { defaults.object(forKey: Key.passiveCardBackfillDone) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.passiveCardBackfillDone) }
    }

    static let reviewDailyLimitRange = 1...500
    static let reviewNewPerDayRange = 0...100
    private static let reviewReminderMinutesRange = 0...1439

    /// Cards per daily review (F-15). Clamped to `reviewDailyLimitRange`.
    var reviewDailyLimit: Int {
        get { clampedInt(Key.reviewDailyLimit, default: 15, range: Self.reviewDailyLimitRange) }
        nonmutating set { defaults.set(newValue.clamped(to: Self.reviewDailyLimitRange), forKey: Key.reviewDailyLimit) }
    }

    /// New cards introduced per review day (ADR-0022). Clamped to `reviewNewPerDayRange`.
    var reviewNewPerDay: Int {
        get { clampedInt(Key.reviewNewPerDay, default: 5, range: Self.reviewNewPerDayRange) }
        nonmutating set { defaults.set(newValue.clamped(to: Self.reviewNewPerDayRange), forKey: Key.reviewNewPerDay) }
    }

    var showFourRatingButtons: Bool {
        get { defaults.object(forKey: Key.showFourRatingButtons) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.showFourRatingButtons) }
    }

    var reviewReminderEnabled: Bool {
        get { defaults.object(forKey: Key.reviewReminderEnabled) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.reviewReminderEnabled) }
    }

    /// Minutes after local midnight, 0...1439. Default 540 (09:00).
    var reviewReminderMinutes: Int {
        get { clampedInt(Key.reviewReminderMinutes, default: 540, range: Self.reviewReminderMinutesRange) }
        nonmutating set {
            defaults.set(newValue.clamped(to: Self.reviewReminderMinutesRange), forKey: Key.reviewReminderMinutes)
        }
    }

    private func clampedInt(_ key: String, default fallback: Int, range: ClosedRange<Int>) -> Int {
        (defaults.object(forKey: key) as? Int).map { $0.clamped(to: range) } ?? fallback
    }

    func colorLabel(for color: HighlightColor) -> String {
        defaults.string(forKey: Key.colorLabel(color)) ?? Self.defaultColorLabel(for: color)
    }

    /// Trimmed. An empty label removes the key, so the default comes back.
    func setColorLabel(_ label: String, for color: HighlightColor) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: Key.colorLabel(color))
        } else {
            defaults.set(trimmed, forKey: Key.colorLabel(color))
        }
    }

    static func defaultColorLabel(for color: HighlightColor) -> String {
        switch color {
        case .yellow: "Key concept"
        case .green: "Exam"
        case .blue: "Connection"
        case .pink: "Question"
        case .purple: "Don't understand"
        }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension SettingsStore {
    /// ID of the "StudyReader" folder the app uses in this Google account's Drive (ADR-0018 amendment). Stored in one
    /// dictionary under "settings.googleAppFolderIds", keyed by `Hashing.sha256Hex(of: email.trimmed.lowercased())`,
    /// so the email itself is never written to the defaults. nil for an empty email.
    func googleAppFolderId(forAccount email: String) -> String? {
        guard let key = Self.accountKey(email) else { return nil }
        return googleAppFolderIds[key]
    }

    /// nil removes the entry. Does nothing for an empty email.
    func setGoogleAppFolderId(_ folderId: String?, forAccount email: String) {
        guard let key = Self.accountKey(email) else { return }
        var all = googleAppFolderIds
        all[key] = folderId
        if all.isEmpty {
            defaults.removeObject(forKey: Key.googleAppFolderIds)
        } else {
            defaults.set(all, forKey: Key.googleAppFolderIds)
        }
    }

    private var googleAppFolderIds: [String: String] {
        defaults.dictionary(forKey: Key.googleAppFolderIds) as? [String: String] ?? [:]
    }

    private static func accountKey(_ email: String) -> String? {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : Hashing.sha256Hex(of: normalized)
    }
}
