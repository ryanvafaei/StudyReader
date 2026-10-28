import Foundation
import Markdown
import SwiftUI

/// One displayed block of a rendered note: a paragraph, heading, list item or rule.
struct NotePreviewBlock: Equatable {
    var text: AttributedString
    var indent: Int
    var isRule: Bool

    /// Parses Markdown into display blocks, because `Text` ignores block structure. Headings are bold and larger,
    /// list items carry their bullet or number once, `indent` is the list nesting depth minus one, and single line
    /// breaks inside a paragraph are kept.
    static func blocks(_ markdown: String) -> [NotePreviewBlock] {
        var result: [NotePreviewBlock] = []
        for child in Markdown.Document(parsing: markdown).children {
            collect(child, depth: 0, prefix: nil, into: &result)
        }
        return result
    }

    /// Appends the blocks for `markup`. `prefix` is a pending list marker for the first block of a list item.
    private static func collect(_ markup: any Markup, depth: Int, prefix: String?, into result: inout [NotePreviewBlock]) {
        switch markup {
        case let heading as Markdown.Heading:
            var text = inline(heading)
            text.font = .headline.bold()
            result.append(NotePreviewBlock(text: text, indent: max(depth - 1, 0), isRule: false))
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
