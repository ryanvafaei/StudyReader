import AppKit
import Foundation
import Markdown

struct MarkdownDocumentSource: Sendable {
    var markdown: String                    // full file text, front matter included
    var documentId: String?                 // for image lookup via FileStore; nil = no local images
    var fileStore: FileStore?
}

/// Not Sendable (NSAttributedString); build and use it in one isolation domain.
struct RenderedMarkdown {
    let attributedString: NSAttributedString
    let sourceMap: MarkdownSourceMap
    /// Search units (ARCHITECTURE §6): a new section starts at each H1 or H2 heading; text before the first one is
    /// section 0 (omitted when empty). Sections partition the string exactly (no gaps, no overlap).
    let sections: [NSRange]
    let frontMatter: FrontMatter
    var string: String { attributedString.string }
}

enum MarkdownRenderer {
    /// Bump when the rendered string can change (triggers re-anchoring, ARCHITECTURE §5.3).
    static let version = 1

    /// Pure and deterministic. Callable off the main actor: only Foundation/AppKit value types
    /// (NSFont, NSColor, NSParagraphStyle, NSImage, NSTextAttachment); no views.
    ///
    /// HTML (blocks and inline) is shown as plain text, never interpreted. Soft breaks render as a space and hard
    /// breaks as U+2028. Images are never fetched from the network.
    static func render(_ source: MarkdownDocumentSource, style: MarkdownRenderStyle = .standard) -> RenderedMarkdown {
        let (frontMatter, body) = FrontMatterParser.split(source.markdown)
        let document = Document(parsing: body)
        var builder = MarkdownBuilder(style: style, source: source)
        builder.renderBlocks(of: document, context: BlockContext())
        return builder.finish(frontMatter: frontMatter)
    }
}

// MARK: - Builder

private struct BlockContext {
    /// Left edge of this block's first line.
    var indent: CGFloat = 0
    var inQuote = false
    var listDepth = 0
    /// Overrides the space after paragraphs (tight list items); nil = the normal paragraph spacing.
    var spacingAfter: CGFloat?
}

/// Everything needed to style one run of text.
private struct InlineStyle {
    var fontSize: CGFloat
    var weight: NSFont.Weight
    var monospacedBlock: Bool
    var color: NSColor
    var paragraphStyle: NSParagraphStyle
    var blockFlags: [NSAttributedString.Key: Bool]
    var traits: InlineTraits = []
    var strikethrough = false
    var linkURL: URL?
    var linkDestination: String?

    var font: NSFont {
        let isCode = traits.contains(.code)
        let size = (isCode && !monospacedBlock) ? fontSize * MarkdownStyle.inlineCodeScale : fontSize
        return MarkdownStyle.font(
            size: size,
            weight: traits.contains(.bold) ? .bold : weight,
            italic: traits.contains(.italic),
            monospaced: isCode || monospacedBlock
        )
    }

    var attributes: [NSAttributedString.Key: Any] {
        var result: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ]
        for (key, value) in blockFlags { result[key] = value }
        if strikethrough { result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let linkURL {
            result[.link] = linkURL
            result[.foregroundColor] = NSColor.linkColor
            result[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return result
    }
}

private struct MarkdownBuilder {
    let style: MarkdownRenderStyle
    let source: MarkdownDocumentSource
    var output = NSMutableAttributedString()
    var entries: [MarkdownSourceMap.Entry] = []
    var sectionStarts: [Int] = []

    private var base: CGFloat { style.baseFontSize }
    private var paragraphSpacing: CGFloat { base * 0.6 }

    init(style: MarkdownRenderStyle, source: MarkdownDocumentSource) {
        self.style = style
        self.source = source
    }

    // MARK: Blocks

    mutating func renderBlocks(of parent: Markup, context: BlockContext) {
        for child in parent.children {
            renderBlock(child, context: context)
        }
    }

    private mutating func renderBlock(_ node: Markup, context: BlockContext) {
        switch node {
        case let heading as Heading: renderHeading(heading, context: context)
        case let paragraph as Paragraph: renderParagraph(paragraph, context: context)
        case let code as CodeBlock: renderCodeBlock(code, context: context)
        case let quote as BlockQuote: renderQuote(quote, context: context)
        case let list as UnorderedList: renderList(list, ordered: nil, context: context)
        case let list as OrderedList: renderList(list, ordered: list, context: context)
        case let table as Table: renderTable(table, context: context)
        case is ThematicBreak: renderRule(context: context)
        case let html as HTMLBlock: renderPlainLines(html.rawHTML, context: context)
        default: renderBlocks(of: node, context: context)
        }
    }

    private func textStyle(
        _ context: BlockContext,
        fontSize: CGFloat? = nil,
        weight: NSFont.Weight = .regular,
        lineHeight: CGFloat = MarkdownStyle.paragraphLineHeight,
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat? = nil,
        firstLineIndent: CGFloat? = nil,
        headIndent: CGFloat? = nil,
        tabStops: [CGFloat] = [],
        monospaced: Bool = false,
        codeBlock: Bool = false
    ) -> InlineStyle {
        var flags: [NSAttributedString.Key: Bool] = [:]
        if context.inQuote { flags[.studyBlockQuote] = true }
        if codeBlock { flags[.studyCodeBlock] = true }
        let paragraph = MarkdownStyle.paragraphStyle(
            firstLineIndent: firstLineIndent ?? context.indent,
            headIndent: headIndent ?? context.indent,
            tabStops: tabStops,
            lineHeightMultiple: lineHeight,
            spacingBefore: spacingBefore,
            spacingAfter: spacingAfter ?? context.spacingAfter ?? paragraphSpacing
        )
        return InlineStyle(
            fontSize: fontSize ?? base,
            weight: weight,
            monospacedBlock: monospaced,
            color: context.inQuote ? NSColor.secondaryLabelColor : NSColor.labelColor,
            paragraphStyle: paragraph,
            blockFlags: flags
        )
    }

    /// Adds the "\n" between two blocks (one character, carrying the previous block's paragraph attributes) and
    /// returns the length to roll back to if the block turns out empty.
    private mutating func beginBlock() -> Int {
        let rollback = output.length
        guard output.length > 0 else { return rollback }
        let last = output.attributes(at: output.length - 1, effectiveRange: nil)
        let kept: [NSAttributedString.Key] = [
            .font, .paragraphStyle, .foregroundColor, .studyCodeBlock, .studyBlockQuote, .studyHorizontalRule,
        ]
        var attributes: [NSAttributedString.Key: Any] = [:]
        for key in kept {
            if let value = last[key] { attributes[key] = value }
        }
        output.append(NSAttributedString(string: "\n", attributes: attributes))
        return rollback
    }

    private mutating func rollBack(to length: Int) {
        output.deleteCharacters(in: NSRange(location: length, length: output.length - length))
        entries.removeAll { $0.range.location >= length }
        sectionStarts.removeAll { $0 >= length }
    }

    private mutating func renderHeading(_ heading: Heading, context: BlockContext) {
        let level = min(max(heading.level, 1), 6)
        let rollback = beginBlock()
        let start = output.length
        let headingStyle = textStyle(
            context,
            fontSize: base * MarkdownStyle.headingScale(level: level),
            weight: level <= 3 ? .bold : .semibold,
            lineHeight: MarkdownStyle.headingLineHeight,
            spacingBefore: base * (level <= 2 ? 0.8 : 0.5),
            spacingAfter: base * 0.4
        )
        appendInlines(of: heading, style: headingStyle)
        if output.length == start {
            rollBack(to: rollback)
        } else if level <= 2 {
            sectionStarts.append(start)
        }
    }

    private mutating func renderParagraph(_ paragraph: Paragraph, context: BlockContext) {
        let rollback = beginBlock()
        let start = output.length
        appendInlines(of: paragraph, style: textStyle(context))
        if output.length == start { rollBack(to: rollback) }
    }

    private mutating func renderCodeBlock(_ code: CodeBlock, context: BlockContext) {
        var lines = code.code
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        while lines.last?.isEmpty == true { lines.removeLast() }
        for (index, line) in lines.enumerated() {
            let isLast = index == lines.count - 1
            var lineStyle = textStyle(
                context,
                fontSize: base * MarkdownStyle.codeBlockScale,
                lineHeight: MarkdownStyle.codeLineHeight,
                spacingAfter: isLast ? nil : 0,
                monospaced: true,
                codeBlock: true
            )
            lineStyle.traits.insert(.code)
            _ = beginBlock()
            appendText(line, style: lineStyle)
        }
    }

    private mutating func renderQuote(_ quote: BlockQuote, context: BlockContext) {
        var inner = context
        inner.indent += MarkdownStyle.quoteIndent
        inner.inQuote = true
        renderBlocks(of: quote, context: inner)
    }

    private mutating func renderRule(context: BlockContext) {
        _ = beginBlock()
        var ruleStyle = textStyle(context)
        ruleStyle.blockFlags[.studyHorizontalRule] = true
        appendText("\u{00A0}", style: ruleStyle)
    }

    /// HTML blocks: the raw text, one paragraph per line, never interpreted.
    private mutating func renderPlainLines(_ text: String, context: BlockContext) {
        var lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeFirst() }
        for line in lines {
            _ = beginBlock()
            appendText(line, style: textStyle(context))
        }
    }

    // MARK: Lists

    private mutating func renderList(_ list: Markup, ordered: OrderedList?, context: BlockContext) {
        var number = Int(ordered?.startIndex ?? 1)
        let items = list.children.compactMap { $0 as? ListItem }
        for (index, item) in items.enumerated() {
            let marker: String
            switch item.checkbox {
            case .checked: marker = "☑\t"
            case .unchecked: marker = "☐\t"
            case nil:
                if ordered != nil {
                    marker = "\(number).\t"
                } else {
                    marker = context.listDepth == 0 ? "•\t" : "◦\t"
                }
            }
            number += 1
            renderListItem(item, marker: marker, isLast: index == items.count - 1, context: context)
        }
    }

    private mutating func renderListItem(_ item: ListItem, marker: String, isLast: Bool, context: BlockContext) {
        let contentIndent = context.indent + MarkdownStyle.listIndent
        let tight = base * 0.25
        let children = Array(item.children)

        func childContext(isLastChild: Bool) -> BlockContext {
            var inner = context
            inner.indent = contentIndent
            inner.listDepth = context.listDepth + 1
            inner.spacingAfter = (isLast && isLastChild) ? context.spacingAfter : tight
            return inner
        }

        var remaining = children[...]
        let markerContext = childContext(isLastChild: children.count <= 1)
        _ = beginBlock()
        let markerStyle = textStyle(
            markerContext,
            firstLineIndent: context.indent,
            headIndent: contentIndent,
            tabStops: [contentIndent]
        )
        appendText(marker, style: markerStyle)
        if let first = remaining.first as? Paragraph {
            appendInlines(of: first, style: markerStyle)
            remaining = remaining.dropFirst()
        }
        for (offset, child) in remaining.enumerated() {
            let isLastChild = offset == remaining.count - 1
            renderBlock(child, context: childContext(isLastChild: isLastChild))
        }
    }

    // MARK: Tables

    private mutating func renderTable(_ table: Table, context: BlockContext) {
        var rows: [(cells: [Table.Cell], isHeader: Bool)] = [(Array(table.head.cells), true)]
        rows += table.body.rows.map { (Array($0.cells), false) }
        let columnCount = max(rows.map(\.cells.count).max() ?? 0, 1)
        let tabStops = (1..<max(columnCount, 2)).map { context.indent + CGFloat($0) * MarkdownStyle.tableColumnWidth }
        for (index, row) in rows.enumerated() {
            let isLast = index == rows.count - 1
            let rowStyle = textStyle(
                context,
                weight: row.isHeader ? .bold : .regular,
                spacingAfter: isLast ? nil : 2,
                tabStops: tabStops
            )
            _ = beginBlock()
            for (cellIndex, cell) in row.cells.enumerated() {
                if cellIndex > 0 { appendText("\t", style: rowStyle) }
                appendInlines(of: cell, style: rowStyle)
            }
        }
    }

    // MARK: Inline content

    private mutating func appendInlines(of parent: Markup, style: InlineStyle) {
        for child in parent.children {
            appendInline(child, style: style)
        }
    }

    private mutating func appendInline(_ node: Markup, style: InlineStyle) {
        switch node {
        case let text as Text:
            appendText(text.string, style: style)
        case is SoftBreak:
            appendText(" ", style: style)
        case is LineBreak:
            appendText("\u{2028}", style: style)
        case let code as InlineCode:
            var inner = style
            inner.traits.insert(.code)
            appendText(code.code, style: inner)
        case is Emphasis:
            var inner = style
            inner.traits.insert(.italic)
            appendInlines(of: node, style: inner)
        case is Strong:
            var inner = style
            inner.traits.insert(.bold)
            appendInlines(of: node, style: inner)
        case is Strikethrough:
            var inner = style
            inner.strikethrough = true
            appendInlines(of: node, style: inner)
        case let link as Link:
            var inner = style
            if let destination = link.destination, let url = URL(string: destination) {
                inner.traits.insert(.link)
                inner.linkURL = url
                inner.linkDestination = destination
            }
            appendInlines(of: node, style: inner)
        case let image as Image:
            appendImage(image, style: style)
        case let html as InlineHTML:
            appendText(html.rawHTML, style: style)
        case let symbol as SymbolLink:
            appendText(symbol.destination ?? "", style: style)
        default:
            appendInlines(of: node, style: style)
        }
    }

    private mutating func appendText(_ string: String, style: InlineStyle) {
        guard !string.isEmpty else { return }
        let start = output.length
        output.append(NSAttributedString(string: string, attributes: style.attributes))
        record(NSRange(location: start, length: output.length - start), style: style)
    }

    private mutating func appendImage(_ image: Image, style: InlineStyle) {
        let attachment = makeAttachment(source: image.source ?? "", alt: image.plainText)
        let start = output.length
        let attachmentString = NSMutableAttributedString(attachment: attachment)
        attachmentString.addAttributes(
            style.attributes,
            range: NSRange(location: 0, length: attachmentString.length)
        )
        output.append(attachmentString)
        record(NSRange(location: start, length: output.length - start), style: style)
    }

    private func makeAttachment(source imageSource: String, alt: String) -> NSTextAttachment {
        let attachment = NSTextAttachment()
        if let local = localImage(forSource: imageSource) {
            attachment.image = local
            let size = local.size
            let width = min(size.width, MarkdownStyle.maxImageWidth)
            attachment.bounds = CGRect(x: 0, y: 0, width: width, height: size.height * width / size.width)
        } else {
            let label: String
            if MarkdownImageNaming.isRemote(imageSource) || alt.isEmpty {
                label = imageSource
            } else {
                label = alt
            }
            let placeholder = MarkdownStyle.placeholderImage(text: label)
            attachment.image = placeholder
            attachment.bounds = CGRect(origin: .zero, size: placeholder.size)
        }
        return attachment
    }

    /// The copied image for a relative source, or nil (remote, invalid, missing or unreadable).
    private func localImage(forSource imageSource: String) -> NSImage? {
        guard let storedName = MarkdownImageNaming.storedFileName(forSource: imageSource),
              let documentId = source.documentId,
              let fileStore = source.fileStore,
              let url = try? fileStore.markdownImageURL(documentId: documentId, storedFileName: storedName),
              let image = NSImage(contentsOf: url),
              image.size.width > 0, image.size.height > 0
        else { return nil }
        return image
    }

    // MARK: Source map

    private mutating func record(_ range: NSRange, style: InlineStyle) {
        guard !style.traits.isEmpty, range.length > 0 else { return }
        if let last = entries.last, NSMaxRange(last.range) == range.location,
           last.traits == style.traits, last.linkDestination == style.linkDestination {
            entries[entries.count - 1].range.length += range.length
        } else {
            entries.append(MarkdownSourceMap.Entry(
                range: range,
                traits: style.traits,
                linkDestination: style.linkDestination
            ))
        }
    }

    // MARK: Result

    /// Trims leading and trailing space, tab and line breaks (U+00A0 is kept: it is the horizontal rule line),
    /// then derives the source map and section ranges for the final string.
    mutating func finish(frontMatter: FrontMatter) -> RenderedMarkdown {
        let units = Array(output.string.utf16)
        func isTrimmable(_ unit: UInt16) -> Bool {
            unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0x2028 || unit == 0x2029
        }
        var leading = 0
        while leading < units.count, isTrimmable(units[leading]) { leading += 1 }
        var trailing = 0
        while trailing < units.count - leading, isTrimmable(units[units.count - 1 - trailing]) { trailing += 1 }
        let keptEnd = units.count - trailing
        if trailing > 0 { output.deleteCharacters(in: NSRange(location: keptEnd, length: trailing)) }
        if leading > 0 { output.deleteCharacters(in: NSRange(location: 0, length: leading)) }
        let length = output.length

        let mapEntries: [MarkdownSourceMap.Entry] = entries.compactMap { entry in
            let start = max(entry.range.location, leading) - leading
            let end = min(NSMaxRange(entry.range), keptEnd) - leading
            guard end > start else { return nil }
            return MarkdownSourceMap.Entry(
                range: NSRange(location: start, length: end - start),
                traits: entry.traits,
                linkDestination: entry.linkDestination
            )
        }

        var boundaries = Set<Int>([0, length])
        for start in sectionStarts {
            boundaries.insert(min(max(start - leading, 0), length))
        }
        let sorted = boundaries.sorted()
        let sections = zip(sorted, sorted.dropFirst()).map { NSRange(location: $0, length: $1 - $0) }

        return RenderedMarkdown(
            attributedString: output,
            sourceMap: MarkdownSourceMap(entries: mapEntries),
            sections: sections,
            frontMatter: frontMatter
        )
    }
}
