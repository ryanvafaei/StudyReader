import Foundation

/// Renders export content to Markdown (ARCHITECTURE §9.1, T70). Pure and golden-file tested.
enum ExportRenderer {
    /// Lines are joined with "\n" and the output ends with exactly one "\n". No line has trailing spaces and there are
    /// never two blank lines in a row. Documents are ordered by title, highlights by `positionKey`, whatever the
    /// order of `content`. Image highlights are dropped when `options.includeImages` is false.
    static func render(
        _ content: ExportContent,
        options: ExportOptions,
        colorLabels: [String],
        generatedAt: Date,
        timeZone: TimeZone
    ) -> String {
        let documents = prepare(content.documents, options: options)
        let highlightCount = documents.reduce(0) { $0 + $1.highlights.count }

        var blocks: [[String]] = [
            ["# StudyReader – \(content.scopeName)"],
            [
                "_Exported \(timestamp(generatedAt, timeZone: timeZone)) · "
                    + "\(count(highlightCount, "highlight")) from \(count(documents.count, "document"))_"
            ],
        ]
        switch options.groupBy {
        case .document:
            blocks += documentBlocks(documents, options: options, colorLabels: colorLabels)
        case .tag:
            blocks += tagBlocks(documents, options: options, colorLabels: colorLabels)
        }
        return assemble(blocks)
    }

    // MARK: Preparation

    /// A document as it will be rendered: sorted, with the dropped highlights removed.
    private struct Prepared {
        var title: String
        var author: String
        var categoryName: String
        var note: String?
        var highlights: [ExportHighlight]
    }

    /// Sorted documents that render at least one highlight or a document note.
    private static func prepare(_ documents: [ExportDocument], options: ExportOptions) -> [Prepared] {
        let sorted = documents.sorted { left, right in
            let order = left.title.localizedStandardCompare(right.title)
            return order == .orderedSame ? left.id < right.id : order == .orderedAscending
        }
        return sorted.compactMap { document in
            let highlights = document.highlights
                .filter { options.includeImages || $0.kind != .image }
                .sorted { ($0.positionKey, $0.id) < ($1.positionKey, $1.id) }
            let note = options.includeDocumentNotes ? document.documentNote : nil
            guard !highlights.isEmpty || note != nil else { return nil }
            return Prepared(
                title: document.title,
                author: document.author,
                categoryName: document.categoryName,
                note: note,
                highlights: highlights
            )
        }
    }

    // MARK: Group by document

    private static func documentBlocks(_ documents: [Prepared], options: ExportOptions, colorLabels: [String]) -> [[String]] {
        var blocks: [[String]] = []
        for document in documents {
            blocks.append(["## \(document.title)"])
            let byline = document.author.isEmpty ? document.categoryName : "\(document.author) · \(document.categoryName)"
            blocks.append(["_\(byline)_"])
            if let note = document.note {
                blocks.append(["### Document note"])
                blocks.append(lines(of: note))
            }
            if !document.highlights.isEmpty {
                blocks.append(["### Highlights"])
                for highlight in document.highlights {
                    blocks.append(itemLines(highlight, options: options, colorLabels: colorLabels, showTags: true))
                }
            }
        }
        return blocks
    }

    // MARK: Group by tag

    private struct TaggedItem {
        var title: String
        var highlight: ExportHighlight
    }

    private static func tagBlocks(_ documents: [Prepared], options: ExportOptions, colorLabels: [String]) -> [[String]] {
        var sections: [String: (name: String, items: [TaggedItem])] = [:]
        var untagged: [TaggedItem] = []
        for document in documents {
            for highlight in document.highlights {
                let item = TaggedItem(title: document.title, highlight: highlight)
                if highlight.tagNames.isEmpty {
                    untagged.append(item)
                }
                for name in highlight.tagNames {
                    let key = name.lowercased()
                    sections[key, default: (name, [])].items.append(item)
                }
            }
        }

        var blocks: [[String]] = []
        let ordered = sections.values.sorted { ($0.name.lowercased(), $0.name) < ($1.name.lowercased(), $1.name) }
        for section in ordered {
            blocks.append(["## #\(section.name)"])
            blocks += section.items.map { taggedBlock($0, options: options, colorLabels: colorLabels) }
        }
        if !untagged.isEmpty {
            blocks.append(["## Untagged"])
            blocks += untagged.map { taggedBlock($0, options: options, colorLabels: colorLabels) }
        }

        let notes = documents.compactMap { document in document.note.map { (document.title, $0) } }
        if !notes.isEmpty {
            blocks.append(["## Document notes"])
            for (title, note) in notes {
                blocks.append(["### \(title)"])
                blocks.append(lines(of: note))
            }
        }
        return blocks
    }

    private static func taggedBlock(_ item: TaggedItem, options: ExportOptions, colorLabels: [String]) -> [String] {
        let page = item.highlight.pageIndex.map { ", p. \($0 + 1)" } ?? ""
        return itemLines(item.highlight, options: options, colorLabels: colorLabels, showTags: false)
            + ["", "  _— \(item.title)\(page)_"]
    }

    // MARK: Highlight item

    private static func itemLines(
        _ highlight: ExportHighlight,
        options: ExportOptions,
        colorLabels: [String],
        showTags: Bool
    ) -> [String] {
        let label = colorLabels.indices.contains(highlight.color.rawValue) ? colorLabels[highlight.color.rawValue] : "Highlight"
        let page = highlight.pageIndex.map { " · p. \($0 + 1)" } ?? ""
        var result = ["- **\(label)**\(page)"]

        let body: String
        if highlight.kind == .image {
            body = highlight.pageIndex.map { "[Image highlight, page \($0 + 1)]" } ?? "[Image highlight]"
        } else {
            body = ExportMarkdownSafety.neutralise(highlight.body)
        }
        result += indented(lines(of: body), by: "  ")

        let note = highlight.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if options.includeNotes, !note.isEmpty {
            let noteLines = lines(of: note)
            result.append("  - Note: \(noteLines[0])")
            result += indented(Array(noteLines.dropFirst()), by: "    ")
        }
        if showTags, !highlight.tagNames.isEmpty {
            result.append("  - Tags: " + highlight.tagNames.map { "#\($0)" }.joined(separator: " "))
        }
        return result
    }

    // MARK: Text helpers

    /// Lines of `text` (trimmed; "\r\n" and "\r" count as "\n"). Blank text has no lines.
    private static func lines(of text: String) -> [String] {
        let normalised = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalised.isEmpty else { return [] }
        return normalised.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func indented(_ lines: [String], by prefix: String) -> [String] {
        lines.map { line in
            line.allSatisfy { $0 == " " || $0 == "\t" } ? "" : prefix + line
        }
    }

    /// Blocks separated by one blank line; trailing spaces removed; blank runs collapsed; one final newline.
    private static func assemble(_ blocks: [[String]]) -> String {
        var output: [String] = []
        for block in blocks where !block.isEmpty {
            if !output.isEmpty { output.append("") }
            for line in block {
                var trimmed = Substring(line)
                while let last = trimmed.last, last == " " || last == "\t" { trimmed.removeLast() }
                if trimmed.isEmpty, output.last?.isEmpty == true { continue }
                output.append(String(trimmed))
            }
        }
        while output.last?.isEmpty == true { output.removeLast() }
        return output.joined(separator: "\n") + "\n"
    }

    private static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
    }

    private static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

/// Neutralises Markdown that Google Docs conversion would parse as block structure or HTML (T58 review, BACKLOG B11).
/// `RichTextMarkdown.escape` already escapes the inline characters; this adds the rest. It runs inside the renderer
/// only, so `ExportHighlight.body` keeps the contract of ARCHITECTURE §9.1.
enum ExportMarkdownSafety {
    /// Backslash-escapes, outside code spans and existing escapes:
    /// - at the start of a line: `#`, `>`, `-`, `+`, `=`, and the `.` or `)` of `1.` / `1)` list markers;
    ///   leading spaces and tabs of a line are dropped (four spaces would start an indented code block);
    /// - anywhere: `<` (HTML, autolinks), `|` (tables), `~` (strikethrough, fences), `&` before a letter or `#`
    ///   (entities), and `!` before an unescaped `[` (images).
    static func neutralise(_ markdown: String) -> String {
        let characters = Array(
            markdown
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
        )
        var output = ""
        output.reserveCapacity(characters.count)
        var index = 0
        var atLineStart = true

        while index < characters.count {
            let character = characters[index]

            if atLineStart {
                if character == " " || character == "\t" {
                    index += 1
                    continue
                }
                if "#>-+=".contains(character) {
                    output.append("\\")
                    output.append(character)
                    index += 1
                    atLineStart = false
                    continue
                }
                if let marker = orderedListMarker(in: characters, at: index) {
                    output += String(characters[index..<marker]) + "\\" + String(characters[marker])
                    index = marker + 1
                    atLineStart = false
                    continue
                }
            }

            atLineStart = false
            switch character {
            case "\n":
                output.append(character)
                atLineStart = true
                index += 1
            case "\\":
                output.append(character)
                if index + 1 < characters.count {
                    output.append(characters[index + 1])
                    atLineStart = characters[index + 1] == "\n"
                    index += 2
                } else {
                    index += 1
                }
            case "`":
                let end = codeSpanEnd(in: characters, from: index)
                output += String(characters[index..<end])
                index = end
            case "<", "|", "~":
                output.append("\\")
                output.append(character)
                index += 1
            case "&":
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                if let next, next == "#" || next.isLetter { output.append("\\") }
                output.append(character)
                index += 1
            case "!":
                if index + 1 < characters.count, characters[index + 1] == "[" { output.append("\\") }
                output.append(character)
                index += 1
            default:
                output.append(character)
                index += 1
            }
        }
        return output
    }

    /// Index of the `.` or `)` when 1 to 9 ASCII digits start at `start` and one of them follows.
    private static func orderedListMarker(in characters: [Character], at start: Int) -> Int? {
        var end = start
        while end < characters.count, end - start < 10, characters[end].isASCII, characters[end].isWholeNumber {
            end += 1
        }
        guard end > start, end - start <= 9, end < characters.count,
              characters[end] == "." || characters[end] == ")" else { return nil }
        return end
    }

    /// End (exclusive) of the code span that opens with the backtick run at `start`, or the end of that run when no
    /// closing run of the same length follows (the backticks are then literal).
    private static func codeSpanEnd(in characters: [Character], from start: Int) -> Int {
        let openLength = runLength(of: "`", in: characters, at: start)
        var cursor = start + openLength
        while cursor < characters.count {
            if characters[cursor] == "`" {
                let length = runLength(of: "`", in: characters, at: cursor)
                if length == openLength { return cursor + length }
                cursor += length
            } else {
                cursor += 1
            }
        }
        return start + openLength
    }

    private static func runLength(of character: Character, in characters: [Character], at start: Int) -> Int {
        var end = start
        while end < characters.count, characters[end] == character { end += 1 }
        return end - start
    }
}
