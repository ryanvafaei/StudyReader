import Foundation

/// Plain-string search shared by the PDF and the text readers (T67). The term is user input and is only ever used as a
/// literal string: no regular expressions, no wildcards.
enum PlainTextFinder {
    /// The options of every in-document match: case and diacritics don't matter, like the library search.
    static let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// The first match of `term` at or after `start` (UTF-16 offset), wrapping to the start of `text`. Whitespace in the
    /// term matches any run of whitespace in the text, so a phrase that wraps over a line break still matches. Nil for
    /// an empty term or no match.
    static func firstRange(of term: String, in text: NSString, from start: Int = 0) -> NSRange? {
        let words = term.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        let length = text.length
        let clamped = min(max(start, 0), length)
        if let found = match(words, in: text, range: NSRange(location: clamped, length: length - clamped)) {
            return found
        }
        guard clamped > 0 else { return nil }
        return match(words, in: text, range: NSRange(location: 0, length: length))
    }

    private static func match(_ words: [String], in text: NSString, range: NSRange) -> NSRange? {
        let length = text.length
        var searchRange = range
        while searchRange.length > 0 {
            let first = text.range(of: words[0], options: options, range: searchRange)
            guard first.location != NSNotFound else { return nil }
            var end = NSMaxRange(first)
            var matched = true
            for word in words.dropFirst() {
                let gapStart = end
                while end < length, isWhitespace(text.character(at: end)) {
                    end += 1
                }
                let next = text.range(
                    of: word,
                    options: options.union(.anchored),
                    range: NSRange(location: end, length: length - end)
                )
                guard end > gapStart, next.location != NSNotFound else {
                    matched = false
                    break
                }
                end = NSMaxRange(next)
            }
            if matched {
                return NSRange(location: first.location, length: end - first.location)
            }
            let resume = first.location + 1
            searchRange = NSRange(location: resume, length: max(NSMaxRange(range) - resume, 0))
        }
        return nil
    }

    private static func isWhitespace(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}
