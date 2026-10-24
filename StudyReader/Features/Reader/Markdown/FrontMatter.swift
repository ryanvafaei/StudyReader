import Foundation

/// The front matter fields StudyReader keeps (SPEC F-03).
struct FrontMatter: Sendable, Equatable {
    var title: String?
    var author: String?
}

enum FrontMatterParser {
    /// If the text (after an optional U+FEFF) starts with a line that is exactly "---", and a later line is exactly
    /// "---" or "...", the lines between are front matter and `body` is everything after the closing line's newline.
    /// Otherwise frontMatter is empty and body is the input unchanged.
    /// Lines are "key: value"; keys compared lowercased; values trimmed, one pair of surrounding
    /// "double" or 'single' quotes removed; empty values → nil. Only title and author are kept.
    /// Line endings "\r\n" are treated like "\n".
    static func split(_ markdown: String) -> (frontMatter: FrontMatter, body: String) {
        let text = markdown.hasPrefix("\u{FEFF}") ? markdown.dropFirst() : Substring(markdown)
        let lines = lines(of: text)
        guard let first = lines.first, first.content == "---" else {
            return (FrontMatter(), markdown)
        }
        guard let closing = lines.indices.dropFirst().first(where: { index in
            lines[index].content == "---" || lines[index].content == "..."
        }) else {
            return (FrontMatter(), markdown)
        }

        var frontMatter = FrontMatter()
        for line in lines[1..<closing] {
            guard let colon = line.content.firstIndex(of: ":") else { continue }
            let key = line.content[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = cleanedValue(line.content[line.content.index(after: colon)...])
            switch key {
            case "title": frontMatter.title = value
            case "author": frontMatter.author = value
            default: continue
            }
        }
        return (frontMatter, String(text[lines[closing].bodyStart...]))
    }

    private struct Line {
        let content: Substring
        /// Index just after this line's newline (or the end of the text).
        let bodyStart: Substring.Index
    }

    /// Splits on `Character.isNewline`, which treats "\r\n" as one line break.
    private static func lines(of text: Substring) -> [Line] {
        var result: [Line] = []
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            var lineEnd = lineStart
            while lineEnd < text.endIndex, !text[lineEnd].isNewline {
                lineEnd = text.index(after: lineEnd)
            }
            let next = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
            result.append(Line(content: text[lineStart..<lineEnd], bodyStart: next))
            lineStart = next
        }
        return result
    }

    private static func cleanedValue(_ raw: Substring) -> String? {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let first = value.first, let last = value.last, first == last,
           first == "\"" || first == "'" {
            value = String(value.dropFirst().dropLast())
        }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
