import Foundation

/// Converts what the user types into a safe FTS5 MATCH expression (SPEC F-12).
///
/// Every piece of user text is emitted inside double quotes with embedded quotes doubled, so
/// nothing typed by the user is ever interpreted as FTS5 syntax. Tokenizing and escaping work on
/// Unicode scalars, not grapheme clusters, so a quote followed by a combining mark is still a quote.
/// NUL characters are ignored. Terms without a letter or a number are dropped, because the `studyreader`
/// tokenizer (ADR-0014) produces no tokens for them: `network +` searches `network`.
/// The parser does no Unicode normalization: the `studyreader` tokenizer handles case, ligatures and soft hyphens.
enum SearchQueryParser {
    struct Term: Equatable, Sendable {
        var text: String          // unquoted user text
        var isPhrase: Bool        // came from "…"
        var isPrefix: Bool        // trailing * on a bare word
        var isNegated: Bool       // leading -
    }

    /// The positive terms and the negated terms as two expressions, so a caller can scope each to its own columns.
    /// `negated` is nil without negated terms; otherwise the negated terms are joined with " OR ", so a row that
    /// matches any of them is excluded. Built from the same terms as `matchExpression(for:)`.
    struct MatchParts: Equatable, Sendable {
        var positive: String
        var negated: String?
    }

    private static let quote: Unicode.Scalar = "\""
    private static let hyphen: Unicode.Scalar = "-"
    private static let asterisk: Unicode.Scalar = "*"
    private static let nul: Unicode.Scalar = "\u{0}"

    /// Tokenizes: whitespace separates terms outside quotes; "…" is one phrase term (an unterminated quote runs to
    /// the end); a leading "-" negates the next word or phrase; a bare word ending in "*" is a prefix term (the "*"
    /// removed; "*" alone or "-" alone is dropped). NUL scalars are skipped as if they weren't in the input. Terms
    /// with no letter or number (including negated ones) are dropped, and so are empty phrases.
    static func terms(in input: String) -> [Term] {
        let scalars = Array(input.unicodeScalars.filter { $0 != nul })
        let count = scalars.count
        var terms: [Term] = []
        var index = 0

        while index < count {
            if isWhitespace(scalars[index]) {
                index += 1
                continue
            }

            var isNegated = false
            if scalars[index] == hyphen {
                isNegated = true
                index += 1
                // A lone "-" (end of input or followed by whitespace) is dropped.
                guard index < count, !isWhitespace(scalars[index]) else { continue }
            }

            if scalars[index] == quote {
                index += 1
                var text = ""
                while index < count, scalars[index] != quote {
                    text.unicodeScalars.append(scalars[index])
                    index += 1
                }
                if index < count {
                    index += 1 // closing quote
                }
                if hasLetterOrNumber(text.unicodeScalars) {
                    terms.append(Term(text: text, isPhrase: true, isPrefix: false, isNegated: isNegated))
                }
            } else {
                var word = String.UnicodeScalarView()
                while index < count, !isWhitespace(scalars[index]) {
                    word.append(scalars[index])
                    index += 1
                }
                var isPrefix = false
                if word.last == asterisk {
                    isPrefix = true
                    word.removeLast()
                }
                if hasLetterOrNumber(word) {
                    terms.append(Term(text: String(word), isPhrase: false, isPrefix: isPrefix, isNegated: isNegated))
                }
            }
        }
        return terms
    }

    /// FTS5 expression, or nil when there is no positive term.
    /// Each term → "\"" + text with every " doubled + "\"" (+ "*" after the closing quote for prefix terms).
    /// Positive terms joined with " AND ", then " NOT " + each negated term.
    /// Example: `neural "gradient descent" back* -cnn` → `"neural" AND "gradient descent" AND "back"* NOT "cnn"`
    static func matchExpression(for input: String) -> String? {
        let terms = terms(in: input)
        let positives = terms.filter { !$0.isNegated }
        guard !positives.isEmpty else { return nil }

        var expression = positives.map(render).joined(separator: " AND ")
        for negated in terms where negated.isNegated {
            expression += " NOT " + render(negated)
        }
        return expression
    }

    /// The same terms as `matchExpression(for:)`, split into the positive expression and the negated expression
    /// (see `MatchParts`). Nil when there is no positive term.
    static func matchParts(for input: String) -> MatchParts? {
        let terms = terms(in: input)
        let positives = terms.filter { !$0.isNegated }
        guard !positives.isEmpty else { return nil }

        let negatives = terms.filter { $0.isNegated }
        return MatchParts(
            positive: positives.map(render).joined(separator: " AND "),
            negated: negatives.isEmpty ? nil : negatives.map(render).joined(separator: " OR ")
        )
    }

    /// The first positive term's text, trimmed (a padded phrase `" a "` gives `a`), for selecting the first match in a
    /// document (T67). Nil when there is none.
    static func firstPositiveTerm(in input: String) -> String? {
        terms(in: input).first { !$0.isNegated }?.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace
    }

    /// True when some scalar is a letter or a number, the characters the `studyreader` tokenizer keeps.
    private static func hasLetterOrNumber<S: Sequence>(_ scalars: S) -> Bool where S.Element == Unicode.Scalar {
        scalars.contains { $0.properties.isAlphabetic || $0.properties.numericType != nil }
    }

    private static func render(_ term: Term) -> String {
        var escaped = ""
        for scalar in term.text.unicodeScalars {
            escaped.unicodeScalars.append(scalar)
            if scalar == quote {
                escaped.unicodeScalars.append(quote)
            }
        }
        return "\"" + escaped + "\"" + (term.isPrefix ? "*" : "")
    }
}
