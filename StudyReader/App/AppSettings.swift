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

    /// Index = `HighlightColor.rawValue` (5 entries).
    private(set) var colorLabels: [String]

    init(store: SettingsStore) {
        self.store = store
        self.defaultCategoryId = store.defaultCategoryId
        self.autoHighlight = store.autoHighlight
        self.currentColor = store.currentColor
        self.invertPDFInDarkMode = store.invertPDFInDarkMode
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
