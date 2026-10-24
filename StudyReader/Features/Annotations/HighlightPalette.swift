import AppKit
import SwiftUI

/// The one place that maps highlight colors to RGB (SPEC F-06).
/// Highlight drawing applies its own alpha; these colors are opaque.
enum HighlightPalette {
    private static func rgb(_ color: HighlightColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        switch color {
        case .yellow: (1.00, 0.85, 0.20)
        case .green: (0.40, 0.80, 0.40)
        case .blue: (0.35, 0.65, 1.00)
        case .pink: (1.00, 0.45, 0.65)
        case .purple: (0.70, 0.50, 0.95)
        }
    }

    static func color(_ color: HighlightColor) -> Color {
        let components = rgb(color)
        return Color(red: components.red, green: components.green, blue: components.blue)
    }

    static func nsColor(_ color: HighlightColor) -> NSColor {
        let components = rgb(color)
        return NSColor(srgbRed: components.red, green: components.green, blue: components.blue, alpha: 1)
    }

    /// Localized color name for accessibility labels.
    static func name(_ color: HighlightColor) -> String {
        switch color {
        case .yellow: String(localized: "yellow")
        case .green: String(localized: "green")
        case .blue: String(localized: "blue")
        case .pink: String(localized: "pink")
        case .purple: String(localized: "purple")
        }
    }
}
