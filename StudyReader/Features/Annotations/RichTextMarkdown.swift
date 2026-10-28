import Foundation

/// Rich text of a highlight as the Markdown subset of SPEC F-07: bold, italic, inline code and links.
enum RichTextMarkdown {
    private static let attachmentCharacter: Character = "\u{FFFC}"

    /// Backslash-escapes \ ` * _ [ ] so the text renders literally as Markdown. Newlines kept.
    static func escape(_ plain: String) -> String {
        var result = ""
        result.reserveCapacity(plain.count)
        for character in plain {
            switch character {
            case "\\", "`", "*", "_", "[", "]":
                result.append("\\")
                result.append(character)
            default:
                result.append(character)
            }
        }
        return result
    }

    /// F-07 subset for `range` of `string`, using sourceMap entries that intersect the range (clipped to it).
    /// Plain parts are escaped. Formatting per run, nesting order: link outermost, then bold, then italic,
    /// then code innermost; code content is not escaped (a longer backtick fence is used if it contains "`").
    /// Touching runs with the same link destination form one link.
    /// Leading/trailing whitespace of a formatted run is moved outside its markers (outside the brackets for a link).
    /// For bold and/or italic (not code) leading/trailing punctuation and symbols are moved outside the emphasis
    /// markers too, so `**"x"**` becomes `"**x**"` and the markers stay valid; a run of only punctuation gets none.
    /// Attachment characters (U+FFFC) are dropped. Other attributes are ignored.
    static func markdown(for range: NSRange, in string: String, sourceMap: MarkdownSourceMap) -> String {
        let text = string as NSString
        let bounds = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard bounds.length > 0 else { return "" }
        let boundsEnd = NSMaxRange(bounds)

        var output = ""
        var cursor = bounds.location
        var link: (destination: String, body: String)?

        func flushLink() {
            guard let pending = link else { return }
            link = nil
            output += linkMarkdown(body: pending.body, destination: pending.destination)
        }

        for entry in sourceMap.entries {
            // Entries ascend by location (MarkdownSourceMap contract), so no later entry can intersect `bounds`.
            if entry.range.location >= boundsEnd { break }
            let clipped = NSIntersectionRange(entry.range, bounds)
            guard clipped.length > 0 else { continue }
            if clipped.location > cursor {
                flushLink()
                output += escape(visibleText(text.substring(with: NSRange(location: cursor, length: clipped.location - cursor))))
            }
            let body = emphasizedRun(text.substring(with: clipped), traits: entry.traits)
            if entry.traits.contains(.link), let destination = entry.linkDestination {
                if link?.destination == destination {
                    link?.body += body
                } else {
                    flushLink()
                    link = (destination, body)
                }
            } else {
                flushLink()
                output += body
            }
            cursor = NSMaxRange(clipped)
        }
        flushLink()
        if cursor < boundsEnd {
            output += escape(visibleText(text.substring(with: NSRange(location: cursor, length: boundsEnd - cursor))))
        }
        return output
    }

    // MARK: Runs

    private static func visibleText(_ text: String) -> String {
        text.filter { $0 != attachmentCharacter }
    }

    /// One run with bold, italic and code applied (no link). Whitespace at either end stays outside the markers.
    private static func emphasizedRun(_ raw: String, traits: InlineTraits) -> String {
        let text = visibleText(raw)
        let isCode = traits.contains(.code)
        let isEmphasized = traits.contains(.bold) || traits.contains(.italic)
        guard isCode || isEmphasized else { return escape(text) }

        let characters = Array(text)
        guard let first = characters.firstIndex(where: { !$0.isWhitespace }),
              let last = characters.lastIndex(where: { !$0.isWhitespace }) else {
            return escape(text)
        }
        let leading = String(characters[..<first])
        let trailing = String(characters[(last + 1)...])
        var core = Array(characters[first...last])
        var leadingPunctuation = ""
        var trailingPunctuation = ""

        if !isCode {
            guard let firstInner = core.firstIndex(where: { !isPunctuationOrSymbol($0) }),
                  let lastInner = core.lastIndex(where: { !isPunctuationOrSymbol($0) }) else {
                return escape(text)
            }
            leadingPunctuation = escape(String(core[..<firstInner]))
            trailingPunctuation = escape(String(core[(lastInner + 1)...]))
            core = Array(core[firstInner...lastInner])
        }

        var body = isCode ? codeSpan(String(core)) : escape(String(core))
        if traits.contains(.italic) { body = "*" + body + "*" }
        if traits.contains(.bold) { body = "**" + body + "**" }
        return leading + leadingPunctuation + body + trailingPunctuation + trailing
    }

    private static func isPunctuationOrSymbol(_ character: Character) -> Bool {
        character.isPunctuation || character.isSymbol
    }

    /// `[body](destination)` with the whitespace at either end of `body` moved outside the brackets.
    private static func linkMarkdown(body: String, destination: String) -> String {
        let characters = Array(body)
        guard let first = characters.firstIndex(where: { !$0.isWhitespace }),
              let last = characters.lastIndex(where: { !$0.isWhitespace }) else {
            return body
        }
        return String(characters[..<first])
            + "[" + String(characters[first...last]) + "](" + escapeDestination(destination) + ")"
            + String(characters[(last + 1)...])
    }

    private static func codeSpan(_ content: String) -> String {
        var longest = 0
        var current = 0
        for character in content {
            if character == "`" {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        let fence = String(repeating: "`", count: longest + 1)
        let needsPadding = content.hasPrefix("`") || content.hasSuffix("`")
        let padding = needsPadding ? " " : ""
        return fence + padding + content + padding + fence
    }

    private static func escapeDestination(_ destination: String) -> String {
        var result = ""
        for character in destination {
            switch character {
            case "(", ")", "\\":
                result.append("\\")
                result.append(character)
            case " ":
                result.append("%20")
            default:
                result.append(character)
            }
        }
        return result
    }
}
