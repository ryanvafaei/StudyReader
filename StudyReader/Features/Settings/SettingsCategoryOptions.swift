import Foundation
import Observation

/// Live category list for the Settings pickers. `observe()` runs from `.task {}` and stays subscribed.
@MainActor @Observable
final class SettingsCategoryOptions {
    private(set) var categories: [DocumentCategory] = []
    private(set) var loadFailed = false

    private let repository: CategoryRepository

    init(repository: CategoryRepository) {
        self.repository = repository
    }

    /// The category the picker should show. Returns `saved` when it is in `categories`. Otherwise (missing
    /// category, or the list not loaded yet) returns the first category's id, and nil when the list is empty.
    /// Display only: the stored setting changes only when the user picks a category.
    static func effectiveSelection(saved: String, in categories: [DocumentCategory]) -> String? {
        if categories.contains(where: { $0.id == saved }) {
            return saved
        }
        return categories.first?.id
    }

    func observe() async {
        do {
            for try await list in repository.observeAll() {
                categories = list
                loadFailed = false
            }
        } catch {
            Log.app.error("Category list failed to load in Settings")
            loadFailed = true
        }
    }
}
