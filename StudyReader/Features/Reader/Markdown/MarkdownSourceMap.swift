import Foundation

/// Inline formatting a rendered run carries (SPEC F-07: rich-text highlights).
struct InlineTraits: OptionSet, Sendable, Hashable {
    let rawValue: Int
    static let bold = InlineTraits(rawValue: 1)
    static let italic = InlineTraits(rawValue: 2)
    static let code = InlineTraits(rawValue: 4)      // inline code and code blocks
    static let link = InlineTraits(rawValue: 8)
}

/// Inline formatting of the rendered string, from Markdown emphasis, strong, code and links.
/// Block styling (headings, table headers, quotes) is not part of it.
struct MarkdownSourceMap: Sendable, Equatable {
    struct Entry: Sendable, Equatable {
        var range: NSRange          // UTF-16 range in the rendered string
        var traits: InlineTraits
        var linkDestination: String?
    }

    /// Sorted by range.location, non-overlapping, covering every rendered character that has traits.
    var entries: [Entry]
}
