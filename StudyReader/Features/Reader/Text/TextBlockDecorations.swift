import AppKit

/// What a paragraph draws behind its text, decided from the block attributes the renderer sets (ARCHITECTURE §7).
enum TextBlockDecoration: Equatable {
    /// Rounded background. The flags say whether the neighbouring paragraph belongs to the same code block, so the
    /// block looks like one box.
    case codeBlock(continuesAbove: Bool, continuesBelow: Bool)
    /// 3 pt bar left of the text; `indent` is the paragraph's head indent.
    case blockQuote(indent: CGFloat)
    case horizontalRule

    static let codeCornerRadius: CGFloat = 6
    static let codeOutset: CGFloat = 6
    static let quoteBarWidth: CGFloat = 3
    /// Distance between the quote bar and the text.
    static let quoteBarGap: CGFloat = 12

    /// The decoration for the paragraph starting at `attributes`, or nil for a plain paragraph.
    /// `previous` and `next` are the attributes of the character before and after the paragraph (nil at the ends).
    static func decoration(
        for attributes: [NSAttributedString.Key: Any],
        previous: [NSAttributedString.Key: Any]?,
        next: [NSAttributedString.Key: Any]?
    ) -> TextBlockDecoration? {
        if attributes[.studyHorizontalRule] as? Bool == true {
            return .horizontalRule
        }
        if attributes[.studyCodeBlock] as? Bool == true {
            return .codeBlock(
                continuesAbove: previous?[.studyCodeBlock] as? Bool == true,
                continuesBelow: next?[.studyCodeBlock] as? Bool == true
            )
        }
        if attributes[.studyBlockQuote] as? Bool == true {
            let style = attributes[.paragraphStyle] as? NSParagraphStyle
            return .blockQuote(indent: style?.firstLineHeadIndent ?? 0)
        }
        return nil
    }

    /// Horizontal position of the quote bar relative to the left edge of the text container.
    static func quoteBarOffset(indent: CGFloat, linePadding: CGFloat) -> CGFloat {
        linePadding + max(0, indent - quoteBarGap)
    }
}

/// A paragraph fragment that draws its block decoration before the text. Plain paragraphs use the default fragment.
final class DecoratedLayoutFragment: NSTextLayoutFragment {
    var decoration: TextBlockDecoration?

    private var columnWidth: CGFloat {
        textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
    }

    private var linePadding: CGFloat {
        textLayoutManager?.textContainer?.lineFragmentPadding ?? 0
    }

    /// The area the decoration covers, relative to the fragment's origin: the whole column, slightly wider for a
    /// code block.
    private var decorationBounds: CGRect {
        let outset = TextBlockDecoration.codeOutset
        return CGRect(
            x: -layoutFragmentFrame.minX - outset,
            y: 0,
            width: columnWidth + 2 * outset,
            height: layoutFragmentFrame.height
        )
    }

    override var renderingSurfaceBounds: CGRect {
        decoration == nil ? super.renderingSurfaceBounds : super.renderingSurfaceBounds.union(decorationBounds)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        if let decoration {
            context.saveGState()
            drawDecoration(decoration, at: point, in: context)
            context.restoreGState()
        }
        super.draw(at: point, in: context)
    }

    private func drawDecoration(_ decoration: TextBlockDecoration, at point: CGPoint, in context: CGContext) {
        let height = layoutFragmentFrame.height
        let columnLeft = point.x - layoutFragmentFrame.minX
        switch decoration {
        case .codeBlock(let continuesAbove, let continuesBelow):
            let radius = TextBlockDecoration.codeCornerRadius
            let outset = TextBlockDecoration.codeOutset
            let visible = CGRect(x: columnLeft - outset, y: point.y, width: columnWidth + 2 * outset, height: height)
            // A neighbour in the same block: extend the box past this fragment and clip, so the corners round only at
            // the ends of the block.
            let box = CGRect(
                x: visible.minX,
                y: visible.minY - (continuesAbove ? radius : 0),
                width: visible.width,
                height: visible.height + (continuesAbove ? radius : 0) + (continuesBelow ? radius : 0)
            )
            context.clip(to: visible)
            context.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.setFillColor(NSColor.quaternarySystemFill.cgColor)
            context.fillPath()
        case .blockQuote(let indent):
            let x = columnLeft + TextBlockDecoration.quoteBarOffset(indent: indent, linePadding: linePadding)
            context.setFillColor(NSColor.separatorColor.cgColor)
            context.fill(CGRect(x: x, y: point.y, width: TextBlockDecoration.quoteBarWidth, height: height))
        case .horizontalRule:
            context.setFillColor(NSColor.separatorColor.cgColor)
            context.fill(CGRect(
                x: columnLeft + linePadding,
                y: point.y + (height / 2).rounded(.down),
                width: max(0, columnWidth - 2 * linePadding),
                height: 1
            ))
        }
    }
}

/// Supplies `DecoratedLayoutFragment` for paragraphs with block attributes. Owned by the controller; the layout
/// manager only holds its delegate weakly.
@MainActor
final class TextBlockDecorationDelegate: NSObject, @preconcurrency NSTextLayoutManagerDelegate {
    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        guard let decoration = Self.decoration(for: textElement, in: textLayoutManager) else {
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }
        let fragment = DecoratedLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.decoration = decoration
        return fragment
    }

    private static func decoration(for element: NSTextElement, in layoutManager: NSTextLayoutManager) -> TextBlockDecoration? {
        guard let paragraph = element as? NSTextParagraph, paragraph.attributedString.length > 0 else { return nil }
        let attributes = paragraph.attributedString.attributes(at: 0, effectiveRange: nil)
        let hasBlockAttribute = attributes[.studyCodeBlock] != nil
            || attributes[.studyBlockQuote] != nil
            || attributes[.studyHorizontalRule] != nil
        guard hasBlockAttribute else { return nil }

        var previous: [NSAttributedString.Key: Any]?
        var next: [NSAttributedString.Key: Any]?
        if let storage = layoutManager.textContentManager as? NSTextContentStorage,
           let text = storage.textStorage,
           let elementRange = element.elementRange {
            let start = storage.offset(from: storage.documentRange.location, to: elementRange.location)
            let end = start + paragraph.attributedString.length
            if start > 0, start <= text.length {
                previous = text.attributes(at: start - 1, effectiveRange: nil)
            }
            if end < text.length {
                next = text.attributes(at: end, effectiveRange: nil)
            }
        }
        return TextBlockDecoration.decoration(for: attributes, previous: previous, next: next)
    }
}
