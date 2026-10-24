import Foundation
@testable import StudyReader

enum TestSettings {
    /// SettingsStore over a fresh suite named "StudyReaderTests-<UUID>". Never `UserDefaults.standard`.
    static func make() -> SettingsStore {
        SettingsStore(suiteName: "StudyReaderTests-\(UUID().uuidString)")
    }

    /// Removes the persistent domain of a store made by `make()`. Does nothing for any other suite.
    static func remove(_ store: SettingsStore) {
        guard let suiteName = store.suiteName, suiteName.hasPrefix("StudyReaderTests-") else { return }
        store.defaults.removePersistentDomain(forName: suiteName)
    }
}
