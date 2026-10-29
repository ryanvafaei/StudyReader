import Foundation

/// Renders export content to Markdown (ARCHITECTURE §9.1, T70). Pure and golden-file tested.
enum ExportRenderer {
    /// Lines are joined with "\n" and the output ends with exactly one "\n". No line has trailing spaces and there are
    /// never two blank lines in a row. Documents are ordered by title, highlights by `positionKey`, whatever the
    /// order of `content`. Image highlights are dropped when `options.includeImages` is false.
    /// Notes go through `ExportMarkdownSafety.note` (ADR-0007 amendment).
    /// Titles, authors and the scope name go through `ExportMarkdownSafety.plainText` (ADR-0007 amendment 2026-10-29).
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
            ["# StudyReader – \(ExportMarkdownSafety.plainText(content.scopeName))"],
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
                title: ExportMarkdownSafety.plainText(document.title),
                author: ExportMarkdownSafety.plainText(document.author),
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
                blocks.append(documentNoteLines(note))
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
                blocks.append(documentNoteLines(note))
            }
        }
        return blocks
    }

    /// A document note's lines. The note is trimmed first, as for highlight notes: leading indentation or blank lines
    /// would otherwise make `note` read the first line as a code indent and skip the heading rule.
    private static func documentNoteLines(_ note: String) -> [String] {
        lines(of: ExportMarkdownSafety.note(note.trimmingCharacters(in: .whitespacesAndNewlines), headings: .demoted))
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
            let noteLines = lines(of: ExportMarkdownSafety.note(note, headings: .bold))
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

/// Makes user text safe for the exported Markdown (T58 review, BACKLOG B11; ADR-0007 amendment 2026-10-28, T87).
/// Three entry points: `neutralise` for highlight text (escapes everything that Google Docs conversion would parse as
/// block structure or HTML; `RichTextMarkdown.escape` already escapes the inline characters, this adds the rest),
/// `note` for notes (keeps inline Markdown and lists, rewrites headings, escapes a line-start `#tag`, `<`, `|`, `~`,
/// closes an open code fence and escapes `=`/`-` underline lines) and `plainText` for plain one-line text: document
/// titles, authors and the scope name (ADR-0007 amendment 2026-10-29, W1).
/// All run inside the renderer only, so `ExportHighlight.body` and `.note` keep the contract of ARCHITECTURE §9.1.
enum ExportMarkdownSafety {
    /// How note headings are rewritten.
    enum NoteHeadings: Sendable {
        /// Document notes (rendered under a `###` heading): levels 1–3 become `####`; levels 4–6 stay.
        case demoted
        /// Highlight notes (inside the `- Note:` list item): any heading line becomes `**text**`.
        case bold
    }

    /// Note Markdown made safe for the export (ADR-0007 amendment 2026-10-28). Keeps inline Markdown, lists, quotes,
    /// links and code; rewrites headings; escapes a line-start `#` that isn't a heading; escapes `<`, `|`, `~`.
    /// Lines that start inside a code span, or whose indentation holds a tab or 4+ spaces, get no heading or `#`
    /// rule (CommonMark reads them as code or list continuation); the inline escapes still apply outside code spans.
    /// A backtick code fence still open at the end of the note gets a closing fence of the opener's length, so it can't
    /// swallow the rest of the export (in `.bold` mode the first line follows `- Note: ` and never opens a fence;
    /// tilde fences need nothing, `~` is escaped). A line made only of `=` or only of `-` (up to 3 leading spaces,
    /// trailing spaces or tabs allowed) gets a backslash, so it is no setext underline and no rule. Not covered, left
    /// as written: spaced or mixed runs (`- - -`, `-- -`, `= =`, `-=`) and thematic breaks of `*` or `_` (`***`,
    /// `* * *`, `___`); they render as a horizontal rule, never as a heading.
    static func note(_ markdown: String, headings: NoteHeadings) -> String {
        let normalised = closingOpenFence(
            in: markdown
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n"),
            headings: headings
        )
        let characters = Array(normalised)
        var output = ""
        output.reserveCapacity(characters.count)
        var index = 0

        while index < characters.count {
            index = noteLine(in: characters, at: index, headings: headings, into: &output)
            if index < characters.count {
                output.append("\n")
                index += 1
            }
        }
        return output
    }

    /// `text` with a closing backtick fence appended when a fence opened at the top level is still open at its end.
    /// CommonMark rules: a fence line is indented by fewer than 4 spaces and no tab; an opener is a run of 3 or more
    /// backticks with no backtick in the rest of the line; a closer is a run at least as long as the opener's, followed
    /// only by spaces and tabs. Lines inside a block are not checked for openers.
    private static func closingOpenFence(in text: String, headings: NoteHeadings) -> String {
        var openLength: Int?
        for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let characters = Array(line)
            var indentEnd = 0
            while indentEnd < characters.count, characters[indentEnd] == " " || characters[indentEnd] == "\t" {
                indentEnd += 1
            }
            let indent = characters[0..<indentEnd]
            guard !indent.contains("\t"), indent.count < 4 else { continue }
            let run = runLength(of: "`", in: characters, at: indentEnd)
            guard run >= 3 else { continue }
            let rest = characters[(indentEnd + run)...]
            if let length = openLength {
                if run >= length, rest.allSatisfy({ $0 == " " || $0 == "\t" }) { openLength = nil }
            } else if !(headings == .bold && number == 0), !rest.contains("`") {
                openLength = run
            }
        }
        guard let length = openLength else { return text }
        return text + "\n" + String(repeating: "`", count: length)
    }

    /// The end of the line at `start` when it holds only `=` or only `-` characters, followed by spaces and tabs.
    private static func underlineEnd(in characters: [Character], from start: Int) -> Int? {
        guard start < characters.count, characters[start] == "=" || characters[start] == "-" else { return nil }
        var end = start + runLength(of: characters[start], in: characters, at: start)
        while end < characters.count, characters[end] == " " || characters[end] == "\t" { end += 1 }
        return end == characters.count || characters[end] == "\n" ? end : nil
    }

    /// Writes the line that starts at `start` (everything up to a line break outside a code span) and returns the
    /// index where it ended: the line break, or the end of `characters`.
    private static func noteLine(
        in characters: [Character],
        at start: Int,
        headings: NoteHeadings,
        into output: inout String
    ) -> Int {
        var indentEnd = start
        while indentEnd < characters.count, characters[indentEnd] == " " || characters[indentEnd] == "\t" {
            indentEnd += 1
        }
        let indent = String(characters[start..<indentEnd])
        let isCodeIndent = indent.contains("\t") || indent.count >= 4

        if !isCodeIndent, let lineEnd = underlineEnd(in: characters, from: indentEnd) {
            output += indent + "\\" + String(characters[indentEnd..<lineEnd])
            return lineEnd
        }

        guard !isCodeIndent, indentEnd < characters.count, characters[indentEnd] == "#" else {
            output += indent
            return escapeInline(in: characters, from: indentEnd, into: &output)
        }

        var lineEnd = indentEnd
        while lineEnd < characters.count, characters[lineEnd] != "\n" { lineEnd += 1 }
        let level = runLength(of: "#", in: characters, at: indentEnd)
        let textStart = indentEnd + level + 1

        if level <= 6, textStart <= lineEnd,
           characters[textStart - 1] == " " || characters[textStart - 1] == "\t",
           let text = headingText(in: characters, from: textStart, to: lineEnd) {
            var escaped = ""
            _ = escapeInline(in: text, from: 0, into: &escaped)
            switch headings {
            case .demoted:
                output += (level <= 3 ? "####" : String(repeating: "#", count: level)) + " " + escaped
            case .bold:
                output += "**" + escaped + "**"
            }
            return lineEnd
        }

        output += indent + "\\"
        return escapeInline(in: characters, from: indentEnd, into: &output)
    }

    /// The text of an ATX heading between `start` and `end`: surrounding spaces and tabs, and a closing `#` sequence,
    /// removed. Nil when nothing is left.
    private static func headingText(in characters: [Character], from start: Int, to end: Int) -> [Character]? {
        func isBlank(_ character: Character) -> Bool { character == " " || character == "\t" }
        var first = start
        var last = end
        while first < last, isBlank(characters[first]) { first += 1 }
        while first < last, isBlank(characters[last - 1]) { last -= 1 }
        var hashStart = last
        while hashStart > first, characters[hashStart - 1] == "#" { hashStart -= 1 }
        if hashStart < last, hashStart == first || isBlank(characters[hashStart - 1]) {
            last = hashStart
            while first < last, isBlank(characters[last - 1]) { last -= 1 }
        }
        return first < last ? Array(characters[first..<last]) : nil
    }

    /// Copies from `start` up to the next line break outside a code span, escaping `<`, `|`, `~` outside code spans
    /// and existing backslash escapes. Returns the index of that line break, or the end of `characters`.
    private static func escapeInline(in characters: [Character], from start: Int, into output: inout String) -> Int {
        var index = start
        while index < characters.count {
            let character = characters[index]
            switch character {
            case "\n":
                return index
            case "\\":
                output.append(character)
                if index + 1 < characters.count, characters[index + 1] != "\n" {
                    output.append(characters[index + 1])
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
            default:
                output.append(character)
                index += 1
            }
        }
        return index
    }

    /// Backslash-escapes, outside code spans and existing escapes:
    /// - at the start of a line: `#`, `>`, `-`, `+`, `=`, and the `.` or `)` of `1.` / `1)` list markers;
    ///   leading spaces and tabs of a line are dropped (four spaces would start an indented code block);
    /// - anywhere: `<` (HTML, autolinks), `|` (tables), `~` (strikethrough, fences), `&` before a letter or `#`
    ///   (entities), and `!` before an unescaped `[` (images).
    /// A code span with line breaks is copied with each line break as a space: CommonMark renders both the same, and
    /// no line inside the span can then start a list or a heading.
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
                let span = String(characters[index..<end])
                output += span.replacingOccurrences(of: "\n", with: " ")
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

    /// Plain text (a document title, an author, the scope name) made safe as inline text on one line of the export
    /// (ADR-0007 amendment 2026-10-29, W1). Line breaks collapse to one space; the text is then escaped like highlight
    /// text (`RichTextMarkdown.escape`, then `neutralise`), and a trailing `#` run after a space is escaped.
    static func plainText(_ plain: String) -> String {
        func isBlank(_ character: Character) -> Bool { character == " " || character == "\t" }
        var pieces: [String] = []
        var current: [Character] = []
        func finishPiece() {
            var piece = current[...]
            while let first = piece.first, isBlank(first) { piece.removeFirst() }
            while let last = piece.last, isBlank(last) { piece.removeLast() }
            if !piece.isEmpty { pieces.append(String(piece)) }
            current = []
        }
        for character in plain {
            if character.isNewline { finishPiece() } else { current.append(character) }
        }
        finishPiece()

        var result = neutralise(RichTextMarkdown.escape(pieces.joined(separator: " ")))
        let characters = Array(result)
        var hashStart = characters.count
        while hashStart > 0, characters[hashStart - 1] == "#" { hashStart -= 1 }
        if hashStart < characters.count, hashStart > 0, isBlank(characters[hashStart - 1]) {
            result = String(characters[..<hashStart]) + "\\" + String(characters[hashStart...])
        }
        return result
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
