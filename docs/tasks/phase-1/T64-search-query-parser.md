# T64: SearchQueryParser

- **Phase:** 1 (E1.6: F-12 query syntax)
- **Agent:** data-layer
- **Depends on:** none
- **ADRs:** docs/decisions/0014-* (tokenizer; the parser does no normalization), ARCHITECTURE §8
- **Visual check needed:** no

## Goal
Turn what the user types into a safe FTS5 MATCH expression (SPEC F-12): words are ANDed, `"exact phrase"`, prefix `word*`, `-word` excludes. All user text is quoted; nothing raw ever reaches MATCH.

## Files to touch
- `StudyReader/Features/Search/SearchQueryParser.swift` (new)
- `StudyReaderTests/SearchTests/SearchQueryParserTests.swift` (new)

## Interfaces to produce
```swift
enum SearchQueryParser {
    struct Term: Equatable, Sendable {
        var text: String          // unquoted user text
        var isPhrase: Bool        // came from "…"
        var isPrefix: Bool        // trailing * on a bare word
        var isNegated: Bool       // leading -
    }
    /// Tokenizes: whitespace separates terms outside quotes; "…" is one phrase term (an unterminated quote runs to
    /// the end); a leading "-" negates the next word or phrase; a bare word ending in "*" is a prefix term (the "*"
    /// removed; "*" alone or "-" alone is dropped). Empty phrases are dropped.
    static func terms(in input: String) -> [Term]

    /// FTS5 expression, or nil when there is no positive term.
    /// Each term → "\"" + text with every " doubled + "\"" (+ "*" after the closing quote for prefix terms).
    /// Positive terms joined with " AND ", then " NOT " + each negated term.
    /// Example: `neural "gradient descent" back* -cnn` → `"neural" AND "gradient descent" AND "back"* NOT "cnn"`
    static func matchExpression(for input: String) -> String?

    /// The first positive term's text (for selecting the first match in a document, T67), or nil.
    static func firstPositiveTerm(in input: String) -> String?
}
```
- Keywords (`AND`, `OR`, `NOT`, `NEAR`) typed by the user are ordinary words (they get quoted).
- No Unicode normalization or lowercasing (the `studyreader` tokenizer does it, ADR-0014).

## Tests (`SearchQueryParserTests`)
- `wordsAreANDed`: `"neural network"` → `"neural" AND "network"`.
- `phrases`: `"\"gradient descent\" loss"` → `"gradient descent" AND "loss"`; unterminated `"\"open phrase"` → `"open phrase"`.
- `prefix`: `"back*"` → `"back"*`; `"*"` → nil.
- `exclusion`: `"cnn -rnn"` → `"cnn" NOT "rnn"`; `"-\"deep nets\" ml"` → `"ml" NOT "deep nets"`; `"-only"` → nil.
- `quotesAreEscaped`: `say"hi` (a bare word containing a quote) → `"say""hi"`; `"a\"b"` input with a phrase containing a doubled quote stays safe (the output contains only balanced quotes).
- `keywordsAreQuoted`: `"NOT AND NEAR"` → `"NOT" AND "AND" AND "NEAR"`.
- `whitespaceOnly`: `"   "` → nil; `"-"` → nil.
- `firstPositiveTerm`: `"-x \"a b\" c"` → `"a b"`.
- `expressionsAreValidFTS`: for every expected expression above, `SELECT count(*) FROM documentText_fts WHERE documentText_fts MATCH ?` on `AppDatabase.makeInMemory()` runs without error (arguments bound, never interpolated).

## Acceptance criteria
1. Phrase, prefix and exclusion queries produce the specified expressions. → tests `SearchQueryParserTests/*` (SPEC F-12 AC2)
2. Every produced expression is valid FTS5 and user text is always quoted. → test `SearchQueryParserTests/expressionsAreValidFTS`

## Out of scope
- Running searches (T65), UI (T66).

## Review log
<!-- Main session appends one line per review: date, model and effort used, verdict, short reason -->
