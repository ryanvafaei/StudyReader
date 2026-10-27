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
    /// Leading/trailing whitespace of a formatted run is moved outside its markers.
    /// Attachment characters (U+FFFC) are dropped. Other attributes are ignored.
    static func markdown(for range: NSRange, in string: String, sourceMap: MarkdownSourceMap) -> String {
        let text = string as NSString
        let bounds = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard bounds.length > 0 else { return "" }

        var output = ""
        var cursor = bounds.location
        for entry in sourceMap.entries {
            let clipped = NSIntersectionRange(entry.range, bounds)
            guard clipped.length > 0 else { continue }
            if clipped.location > cursor {
                output += escape(visibleText(text.substring(with: NSRange(location: cursor, length: clipped.location - cursor))))
            }
            output += formattedRun(text.substring(with: clipped), traits: entry.traits, link: entry.linkDestination)
            cursor = NSMaxRange(clipped)
        }
        if cursor < NSMaxRange(bounds) {
            output += escape(visibleText(text.substring(with: NSRange(location: cursor, length: NSMaxRange(bounds) - cursor))))
        }
        return output
    }

    // MARK: Runs

    private static func visibleText(_ text: String) -> String {
        text.filter { $0 != attachmentCharacter }
    }

    private static func formattedRun(_ raw: String, traits: InlineTraits, link: String?) -> String {
        let text = visibleText(raw)
        let hasLink = traits.contains(.link) && link != nil
        let isFormatted = hasLink || traits.contains(.bold) || traits.contains(.italic) || traits.contains(.code)
        guard isFormatted else { return escape(text) }

        let characters = Array(text)
        guard let first = characters.firstIndex(where: { !$0.isWhitespace }),
              let last = characters.lastIndex(where: { !$0.isWhitespace }) else {
            return escape(text)
        }
        let leading = String(characters[..<first])
        let core = String(characters[first...last])
        let trailing = String(characters[(last + 1)...])

        var body = traits.contains(.code) ? codeSpan(core) : escape(core)
        if traits.contains(.italic) { body = "*" + body + "*" }
        if traits.contains(.bold) { body = "**" + body + "**" }
        if hasLink, let link { body = "[" + body + "](" + escapeDestination(link) + ")" }
        return leading + body + trailing
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
