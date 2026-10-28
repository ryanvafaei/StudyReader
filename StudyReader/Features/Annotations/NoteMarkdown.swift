import Foundation
import Markdown
import SwiftUI

/// One rendered block of a note: a paragraph, list item, heading or thematic break.
struct NotePreviewBlock: Equatable {
    var text: AttributedString
    /// List nesting depth minus one.
    var indent: Int
    /// A thematic break.
    var isRule: Bool
    /// 0 = not a heading; 1...6 = ATX level.
    var headingLevel: Int = 0
}

enum NoteMarkdownStyle: Sendable {
    /// Notes tab preview: body text `.body`.
    case regular
    /// List rows (reader panel, browser): body text `.callout`.
    case compact
}

enum NoteMarkdown {
    /// Parses the full Markdown syntax into one block per paragraph, list item, heading or rule, because `Text`
    /// ignores block structure. List items carry their bullet or number once, `indent` is the list nesting depth
    /// minus one, and single line breaks inside a paragraph are kept. Heading blocks have `headingLevel` set and
    /// contain only the heading text. `#name` without a space is paragraph text.
    static func blocks(_ markdown: String) -> [NotePreviewBlock] {
        var result: [NotePreviewBlock] = []
        for child in Markdown.Document(parsing: markdown).children {
            collect(child, depth: 0, prefix: nil, into: &result)
        }
        return result
    }

    /// Font of a heading block; nil for level 0 (use the style's body font).
    static func headingFont(level: Int, style: NoteMarkdownStyle) -> Font? {
        guard level > 0 else { return nil }
        switch style {
        case .regular:
            switch level {
            case 1: return .title2.bold()
            case 2: return .title3.bold()
            default: return .headline
            }
        case .compact:
            switch level {
            case 1: return .title3.bold()
            case 2: return .headline
            default: return .callout.bold()
            }
        }
    }

    /// Appends the blocks for `markup`. `prefix` is a pending list marker for the first block of a list item.
    private static func collect(_ markup: any Markup, depth: Int, prefix: String?, into result: inout [NotePreviewBlock]) {
        switch markup {
        case let heading as Markdown.Heading:
            result.append(NotePreviewBlock(
                text: inline(heading), indent: max(depth - 1, 0), isRule: false, headingLevel: heading.level
            ))
        case let paragraph as Markdown.Paragraph:
            result.append(NotePreviewBlock(
                text: AttributedString(prefix ?? "") + inline(paragraph),
                indent: max(depth - 1, 0),
                isRule: false
            ))
        case is Markdown.ThematicBreak:
            result.append(NotePreviewBlock(text: AttributedString(), indent: 0, isRule: true))
        case let list as Markdown.UnorderedList:
            for item in list.listItems { collectItem(item, depth: depth + 1, marker: "\u{2022} ", into: &result) }
        case let list as Markdown.OrderedList:
            for (offset, item) in list.listItems.enumerated() {
                collectItem(item, depth: depth + 1, marker: "\(Int(list.startIndex) + offset). ", into: &result)
            }
        case let quote as Markdown.BlockQuote:
            for child in quote.children { collect(child, depth: depth, prefix: nil, into: &result) }
        case let code as Markdown.CodeBlock:
            var text = AttributedString(prefix ?? "") + AttributedString(code.code.trimmingCharacters(in: .newlines))
            text.inlinePresentationIntent = .code
            result.append(NotePreviewBlock(text: text, indent: max(depth - 1, 0), isRule: false))
        default:
            let raw = markup.format().trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty {
                result.append(NotePreviewBlock(
                    text: AttributedString((prefix ?? "") + raw), indent: max(depth - 1, 0), isRule: false
                ))
            }
        }
    }

    /// Only the first block of an item gets the marker; later blocks of the same item don't.
    private static func collectItem(
        _ item: Markdown.ListItem, depth: Int, marker: String, into result: inout [NotePreviewBlock]
    ) {
        var pending: String? = marker
        for child in item.children {
            let isList = child is Markdown.UnorderedList || child is Markdown.OrderedList
            collect(child, depth: depth, prefix: isList ? nil : pending, into: &result)
            if !isList { pending = nil }
        }
    }

    private static func inline(_ container: any Markup) -> AttributedString {
        var result = AttributedString()
        for child in container.children { result += inlineNode(child) }
        return result
    }

    private static func inlineNode(_ markup: any Markup) -> AttributedString {
        switch markup {
        case let text as Markdown.Text:
            return AttributedString(text.string)
        case is Markdown.SoftBreak, is Markdown.LineBreak:
            return AttributedString("\n")
        case let code as Markdown.InlineCode:
            var text = AttributedString(code.code)
            text.inlinePresentationIntent = .code
            return text
        case is Markdown.Strong:
            return styled(inline(markup), .stronglyEmphasized)
        case is Markdown.Emphasis:
            return styled(inline(markup), .emphasized)
        case is Markdown.Strikethrough:
            return styled(inline(markup), .strikethrough)
        case let link as Markdown.Link:
            var text = inline(link)
            if let destination = link.destination, let url = URL(string: destination) { text.link = url }
            return text
        case let image as Markdown.Image:
            return AttributedString(image.plainText)
        case let html as Markdown.InlineHTML:
            return AttributedString(html.rawHTML)
        default:
            return AttributedString(markup.format())
        }
    }

    private static func styled(_ text: AttributedString, _ intent: InlinePresentationIntent) -> AttributedString {
        var result = text
        for run in text.runs {
            result[run.range].inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(intent)
        }
        return result
    }
}

/// Renders note Markdown with `NoteMarkdown.blocks`. The only view that renders notes (panel rows, browser rows,
/// Notes tab preview).
struct NoteMarkdownView: View {
    private let blocks: [NotePreviewBlock]
    private let style: NoteMarkdownStyle

    init(_ markdown: String, style: NoteMarkdownStyle = .regular, maxBlocks: Int? = nil) {
        let parsed = NoteMarkdown.blocks(markdown)
        var blocks = parsed.isEmpty && !markdown.isEmpty
            ? [NotePreviewBlock(text: AttributedString(markdown), indent: 0, isRule: false)]
            : parsed
        if let maxBlocks { blocks = Array(blocks.prefix(maxBlocks)) }
        self.blocks = blocks
        self.style = style
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .regular ? 6 : 2) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                if block.isRule {
                    Divider()
                } else {
                    blockText(block)
                }
            }
        }
        .studyReaderLinkPolicy()
    }

    @ViewBuilder
    private func blockText(_ block: NotePreviewBlock) -> some View {
        let text = Text(block.text)
            .font(NoteMarkdown.headingFont(level: block.headingLevel, style: style) ?? bodyFont)
            .padding(.leading, CGFloat(block.indent) * 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        if style == .compact {
            text.lineLimit(2)
        } else {
            text
        }
    }

    private var bodyFont: Font { style == .regular ? .body : .callout }
}
