import Foundation

/// Creates and re-finds `TextAnchor`s (ARCHITECTURE §5.2–§5.3, ADR-0004). Pure: works on `String`/`NSString` only.
/// All offsets are UTF-16 (`NSRange`).
enum TextAnchoring {
    /// Context kept before and after the anchored text, in UTF-16 units, widened so no composed character is split.
    static let contextLength = 32
    /// Search window around the old start, in UTF-16 units (ARCHITECTURE §5.3 step 1).
    static let nearbyWindow = 2_000

    /// text = substring at range; prefix/suffix = up to `contextLength` UTF-16 units before/after, adjusted outward
    /// to composed-character boundaries.
    static func anchor(for range: NSRange, in text: String, sourceVersion: Int) -> TextAnchor {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let clamped = NSIntersectionRange(range, full)
        let location = range.location > full.length ? full.length : clamped.location
        let selected = NSRange(location: location, length: clamped.length)

        var prefixStart = max(0, selected.location - contextLength)
        if prefixStart < selected.location {
            let widened = ns.rangeOfComposedCharacterSequences(
                for: NSRange(location: prefixStart, length: selected.location - prefixStart))
            prefixStart = widened.location
        }
        var suffixEnd = min(full.length, NSMaxRange(selected) + contextLength)
        if suffixEnd > NSMaxRange(selected) {
            let widened = ns.rangeOfComposedCharacterSequences(
                for: NSRange(location: NSMaxRange(selected), length: suffixEnd - NSMaxRange(selected)))
            suffixEnd = NSMaxRange(widened)
        }

        return TextAnchor(
            start: selected.location,
            length: selected.length,
            text: ns.substring(with: selected),
            prefix: ns.substring(with: NSRange(location: prefixStart, length: selected.location - prefixStart)),
            suffix: ns.substring(with: NSRange(location: NSMaxRange(selected), length: suffixEnd - NSMaxRange(selected))),
            sourceVersion: sourceVersion
        )
    }

    enum Resolution: Equatable, Sendable {
        /// Same version and the stored range still holds `anchor.text`.
        case unchanged
        /// Found: new start/length, `sourceVersion` = current version, same text/prefix/suffix.
        case moved(TextAnchor)
        /// Not found anywhere.
        case orphaned
    }

    static func resolve(_ anchor: TextAnchor, in text: String, currentVersion: Int) -> Resolution {
        var resolver = Resolver(text: text)
        return resolver.resolve(anchor, currentVersion: currentVersion)
    }

    /// Re-finds anchors in one text. Builds the normalised text lazily, at most once, and only when an anchor's
    /// stored range no longer holds its text.
    struct Resolver {
        private let text: NSString
        private let string: String
        private var normalized: NormalizedText?
        /// How often the normalised text was built (0 or 1). Test hook.
        private(set) var normalizedBuildCount = 0

        /// True once an anchor needed the normalised text. Test hook.
        var hasBuiltNormalizedText: Bool { normalized != nil }

        init(text: String) {
            self.string = text
            self.text = text as NSString
        }

        mutating func resolve(_ anchor: TextAnchor, currentVersion: Int) -> Resolution {
            guard !anchor.text.isEmpty else { return .orphaned }

            let stored = NSRange(location: anchor.start, length: anchor.length)
            if anchor.start >= 0, anchor.length >= 0, NSMaxRange(stored) <= text.length,
               text.substring(with: stored) == anchor.text {
                if anchor.sourceVersion == currentVersion { return .unchanged }
                return .moved(TextAnchoring.moved(anchor, to: stored, version: currentVersion))
            }

            let haystack = normalizedText()
            let needle = NormalizedText(anchor.text).units
            let prefix = NormalizedText(anchor.prefix).units
            let suffix = NormalizedText(anchor.suffix).units
            guard !needle.isEmpty, needle.count <= haystack.units.count else { return .orphaned }

            let oldStart = haystack.normalizedOffset(forOriginal: anchor.start)
            let lastStart = haystack.units.count - needle.count
            let windowLower = max(0, oldStart - nearbyWindow)
            let windowUpper = min(lastStart, oldStart + nearbyWindow)
            var candidates = windowLower <= windowUpper
                ? occurrences(of: needle, in: haystack.units, starts: windowLower...windowUpper)
                : []
            if candidates.isEmpty { candidates = occurrences(of: needle, in: haystack.units, starts: 0...lastStart) }

            var best: (start: Int, score: Int, distance: Int)?
            for start in candidates {
                let score = commonSuffixLength(prefix, haystack.units, before: start)
                    + commonPrefixLength(suffix, haystack.units, from: start + needle.count)
                let distance = abs(start - oldStart)
                if let current = best {
                    if score < current.score || (score == current.score && distance >= current.distance) { continue }
                }
                best = (start, score, distance)
            }
            guard let winner = best else { return .orphaned }

            let originalStart = haystack.originalStarts[winner.start]
            let originalEnd = haystack.originalEnds[winner.start + needle.count - 1]
            let range = NSRange(location: originalStart, length: originalEnd - originalStart)
            return .moved(TextAnchoring.moved(anchor, to: range, version: currentVersion))
        }

        private mutating func normalizedText() -> NormalizedText {
            if let normalized { return normalized }
            let built = NormalizedText(string)
            normalized = built
            normalizedBuildCount += 1
            return built
        }
    }

    /// positionKey for text/Markdown highlights (ARCHITECTURE §5.5).
    static func positionKey(for anchor: TextAnchor) -> Double {
        Double(anchor.start)
    }

    // MARK: - Helpers

    private static func moved(_ anchor: TextAnchor, to range: NSRange, version: Int) -> TextAnchor {
        var result = anchor
        result.start = range.location
        result.length = range.length
        result.sourceVersion = version
        return result
    }

    /// Start offsets of every (possibly overlapping) occurrence of `needle` that begins inside `starts`, ascending.
    private static func occurrences(of needle: [UInt16], in haystack: [UInt16], starts: ClosedRange<Int>) -> [Int] {
        guard let first = needle.first, needle.count <= haystack.count else { return [] }
        var result: [Int] = []
        var index = max(starts.lowerBound, 0)
        let last = min(starts.upperBound, haystack.count - needle.count)
        while index <= last {
            if haystack[index] == first {
                var offset = 1
                while offset < needle.count, haystack[index + offset] == needle[offset] { offset += 1 }
                if offset == needle.count { result.append(index) }
            }
            index += 1
        }
        return result
    }

    /// Length of the common suffix of `context` and `text[0..<end]`.
    private static func commonSuffixLength(_ context: [UInt16], _ text: [UInt16], before end: Int) -> Int {
        var count = 0
        while count < context.count, count < end,
              context[context.count - 1 - count] == text[end - 1 - count] {
            count += 1
        }
        return count
    }

    /// Length of the common prefix of `context` and `text[start...]`.
    private static func commonPrefixLength(_ context: [UInt16], _ text: [UInt16], from start: Int) -> Int {
        var count = 0
        while count < context.count, start + count < text.count, context[count] == text[start + count] {
            count += 1
        }
        return count
    }
}

/// A string with every run of whitespace/newlines collapsed to one space, plus the map from normalized UTF-16
/// offsets back to original ones.
private struct NormalizedText {
    var units: [UInt16] = []
    /// Original offset of the first unit that produced each normalized unit.
    var originalStarts: [Int] = []
    /// Original offset just past the last unit that produced each normalized unit.
    var originalEnds: [Int] = []
    /// Normalized index for each original offset 0...count (the end offset maps to `units.count`).
    private var normalizedForOriginal: [Int] = []

    init(_ text: String) {
        let original = Array(text.utf16)
        units.reserveCapacity(original.count)
        originalStarts.reserveCapacity(original.count)
        originalEnds.reserveCapacity(original.count)
        normalizedForOriginal.reserveCapacity(original.count + 1)

        var index = 0
        while index < original.count {
            if Self.isWhitespace(original[index]) {
                let runStart = index
                while index < original.count, Self.isWhitespace(original[index]) {
                    normalizedForOriginal.append(units.count)
                    index += 1
                }
                units.append(0x20)
                originalStarts.append(runStart)
                originalEnds.append(index)
            } else {
                normalizedForOriginal.append(units.count)
                units.append(original[index])
                originalStarts.append(index)
                originalEnds.append(index + 1)
                index += 1
            }
        }
        normalizedForOriginal.append(units.count)
    }

    func normalizedOffset(forOriginal offset: Int) -> Int {
        normalizedForOriginal[min(max(offset, 0), normalizedForOriginal.count - 1)]
    }

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        Unicode.Scalar(unit)?.properties.isWhitespace ?? false
    }
}
