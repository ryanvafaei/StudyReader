import Foundation

/// The key mapping both readers share for highlighting the selection (SPEC F-06).
enum HighlightKeys {
    /// The color a key press picks: "1"–"5" are `HighlightColor` raw values 0–4, "h"/"H" the current color. Nil for
    /// other keys.
    static func color(forKey key: String?, current: HighlightColor) -> HighlightColor? {
        guard let key, key.count == 1 else { return nil }
        if key.lowercased() == "h" {
            return current
        }
        guard let digit = Int(key), (1...5).contains(digit) else { return nil }
        return HighlightColor(rawValue: digit - 1)
    }
}
