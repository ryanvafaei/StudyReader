import AppKit

struct MarkdownRenderStyle: Sendable, Equatable {
    var baseFontSize: CGFloat = 16          // F-05 default; appearance settings arrive in Phase 3
    static let standard = MarkdownRenderStyle()
}

extension NSAttributedString.Key {
    /// Bool; the text view draws a background (T55).
    static let studyCodeBlock = NSAttributedString.Key("studyCodeBlock")
    /// Bool; the text view draws a left bar (T55).
    static let studyBlockQuote = NSAttributedString.Key("studyBlockQuote")
    /// Bool; the text view draws the rule on the U+00A0 line.
    static let studyHorizontalRule = NSAttributedString.Key("studyHorizontalRule")
}

/// Sizes, fonts and paragraph styles for the renderer. Pure value construction; safe off the main actor.
enum MarkdownStyle {
    /// Heading font size multipliers for H1…H6.
    static let headingScales: [CGFloat] = [2.0, 1.6, 1.35, 1.2, 1.05, 1.0]
    static let codeBlockScale: CGFloat = 0.9
    static let inlineCodeScale: CGFloat = 0.9
    static let paragraphLineHeight: CGFloat = 1.4
    static let headingLineHeight: CGFloat = 1.2
    static let codeLineHeight: CGFloat = 1.2
    static let listIndent: CGFloat = 20
    static let quoteIndent: CGFloat = 16
    static let maxImageWidth: CGFloat = 720
    static let tableColumnWidth: CGFloat = 140
    static let placeholderSize = NSSize(width: 320, height: 56)

    static func headingScale(level: Int) -> CGFloat {
        headingScales[min(max(level, 1), headingScales.count) - 1]
    }

    static func font(size: CGFloat, weight: NSFont.Weight, italic: Bool, monospaced: Bool) -> NSFont {
        let base = monospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        guard italic else { return base }
        let descriptor = base.fontDescriptor
        let italicDescriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.italic))
        return NSFont(descriptor: italicDescriptor, size: size) ?? base
    }

    static func paragraphStyle(
        firstLineIndent: CGFloat,
        headIndent: CGFloat,
        tabStops: [CGFloat],
        lineHeightMultiple: CGFloat,
        spacingBefore: CGFloat,
        spacingAfter: CGFloat
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = firstLineIndent
        style.headIndent = headIndent
        style.lineHeightMultiple = lineHeightMultiple
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        if !tabStops.isEmpty {
            style.tabStops = tabStops.map { NSTextTab(textAlignment: .left, location: $0) }
        }
        return style
    }

    /// A rounded box with the text centered; used for remote, missing and unreadable images.
    static func placeholderImage(text: String) -> NSImage {
        NSImage(size: placeholderSize, flipped: false) { rect in
            let box = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
            NSColor.quaternaryLabelColor.setFill()
            box.fill()
            NSColor.tertiaryLabelColor.setStroke()
            box.lineWidth = 1
            box.stroke()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingMiddle
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
            let textHeight = ceil(NSFont.systemFont(ofSize: 13).boundingRectForFont.height)
            let textRect = NSRect(
                x: rect.minX + 12,
                y: rect.midY - textHeight / 2,
                width: rect.width - 24,
                height: textHeight
            )
            (text as NSString).draw(in: textRect, withAttributes: attributes)
            return true
        }
    }
}
