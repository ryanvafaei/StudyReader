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

    /// A filled circle in `nsColor(color)` with a 0.5 pt `NSColor.separatorColor` outline, `diameter` points wide.
    /// `isTemplate == false`, so menus draw it in its own colour in light and dark mode.
    static func swatchImage(_ color: HighlightColor, diameter: CGFloat = 12) -> NSImage {
        let image = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            let oval = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            nsColor(color).setFill()
            oval.fill()
            NSColor.separatorColor.setStroke()
            oval.lineWidth = 0.5
            oval.stroke()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = name(color)
        return image
    }

    /// Capitalized colour name for row labels: "Yellow", "Green", "Blue", "Pink", "Purple" (SPEC F-06).
    /// `name(_:)` stays lowercase for use inside sentences.
    static func title(_ color: HighlightColor) -> String {
        switch color {
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .blue: String(localized: "Blue")
        case .pink: String(localized: "Pink")
        case .purple: String(localized: "Purple")
        }
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
