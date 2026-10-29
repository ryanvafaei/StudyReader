import Foundation

/// One hidden span: UTF-16 offsets into the cloze card's text (reviewCard.answer, ADR-0021).
struct ClozeRange: Codable, Sendable, Hashable {
    var location: Int
    var length: Int
    var pair: [Int] { [location, length] }       // reviewCard.clozeRanges element
}

/// Cloze display (ARCHITECTURE §10.3): the front hides each range, the back emphasises it.
enum ClozeText {
    /// Markdown for the hidden span (renders as "[…]").
    static let placeholderMarkdown = "\\[…\\]"

    /// Keeps only pairs with exactly 2 values, location >= 0, length > 0, location + length <= text.utf16.count;
    /// sorts by location; merges overlapping ranges (not merely touching ones).
    static func normalized(_ pairs: [[Int]], in text: String) -> [ClozeRange] {
        let count = text.utf16.count
        let valid = pairs.compactMap { pair -> ClozeRange? in
            guard pair.count == 2 else { return nil }
            let location = pair[0]
            let length = pair[1]
            guard location >= 0, location <= count, length > 0, length <= count - location else { return nil }
            return ClozeRange(location: location, length: length)
        }
        .sorted { $0.location < $1.location }

        var merged: [ClozeRange] = []
        for range in valid {
            if let last = merged.last, range.location < last.location + last.length {
                let end = max(last.location + last.length, range.location + range.length)
                merged[merged.count - 1].length = end - last.location
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// Text outside the ranges through RichTextMarkdown.escape; each range replaced by placeholderMarkdown.
    static func front(_ text: String, ranges: [ClozeRange]) -> String {
        render(text, ranges: ranges) { _ in placeholderMarkdown }
    }

    /// Text outside the ranges escaped; each range's text escaped and wrapped in "**…**", with any leading or trailing
    /// whitespace of the range moved outside the markers (CommonMark ignores "** word**"). A whitespace-only range is
    /// written without markers.
    static func back(_ text: String, ranges: [ClozeRange]) -> String {
        render(text, ranges: ranges) { hidden in
            let characters = Array(hidden)
            guard let first = characters.firstIndex(where: { !$0.isWhitespace }),
                  let last = characters.lastIndex(where: { !$0.isWhitespace }) else {
                return RichTextMarkdown.escape(hidden)
            }
            let leading = String(characters[..<first])
            let core = String(characters[first...last])
            let trailing = String(characters[(last + 1)...])
            return leading + "**" + RichTextMarkdown.escape(core) + "**" + trailing
        }
    }

    /// Walks `ranges` (normalized, ascending) and renders the gaps escaped and each range with `hidden`.
    private static func render(_ text: String, ranges: [ClozeRange], hidden: (String) -> String) -> String {
        let units = Array(text.utf16)
        var output = ""
        var cursor = 0
        for range in ranges {
            guard range.location >= cursor, range.length > 0, range.location + range.length <= units.count else {
                continue
            }
            output += RichTextMarkdown.escape(substring(units, cursor..<range.location))
            output += hidden(substring(units, range.location..<(range.location + range.length)))
            cursor = range.location + range.length
        }
        output += RichTextMarkdown.escape(substring(units, cursor..<units.count))
        return output
    }

    private static func substring(_ units: [UInt16], _ range: Range<Int>) -> String {
        String(decoding: units[range], as: UTF16.self)
    }
}
