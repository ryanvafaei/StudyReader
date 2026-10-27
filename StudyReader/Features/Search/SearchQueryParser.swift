import Foundation

/// Converts what the user types into a safe FTS5 MATCH expression (SPEC F-12).
///
/// Every piece of user text is emitted inside double quotes with embedded quotes doubled, so
/// nothing typed by the user is ever interpreted as FTS5 syntax. Tokenizing and escaping work on
/// Unicode scalars, not grapheme clusters, so a quote followed by a combining mark is still a quote.
/// The parser does no Unicode normalization: the `studyreader` tokenizer (ADR-0014) handles case,
/// ligatures and soft hyphens.
enum SearchQueryParser {
    struct Term: Equatable, Sendable {
        var text: String          // unquoted user text
        var isPhrase: Bool        // came from "…"
        var isPrefix: Bool        // trailing * on a bare word
        var isNegated: Bool       // leading -
    }

    private static let quote: Unicode.Scalar = "\""
    private static let hyphen: Unicode.Scalar = "-"
    private static let asterisk: Unicode.Scalar = "*"

    /// Tokenizes: whitespace separates terms outside quotes; "…" is one phrase term (an unterminated quote runs to
    /// the end); a leading "-" negates the next word or phrase; a bare word ending in "*" is a prefix term (the "*"
    /// removed; "*" alone or "-" alone is dropped). Empty phrases are dropped.
    static func terms(in input: String) -> [Term] {
        let scalars = Array(input.unicodeScalars)
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
                if !text.unicodeScalars.allSatisfy(isWhitespace) {
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
                if !word.isEmpty {
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

    /// The first positive term's text (for selecting the first match in a document, T67), or nil.
    static func firstPositiveTerm(in input: String) -> String? {
        terms(in: input).first { !$0.isNegated }?.text
    }

    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace
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
