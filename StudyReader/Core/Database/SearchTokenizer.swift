import Foundation
import GRDB

/// Token normalization for full-text search (ADR-0014). Index text and MATCH queries both pass through it.
/// Changing anything here changes the index format: it needs a new migration that rebuilds all FTS tables.
enum SearchTokenNormalizer {
    /// Kept inside tokens by unicode61, then removed by normalize(_:): U+00AD soft hyphen.
    static let joinerScalars: [Unicode.Scalar] = ["\u{00AD}"]

    /// joinerScalars as one String, for the unicode61 `tokenchars` argument.
    static var tokenCharacters: String {
        String(String.UnicodeScalarView(joinerScalars))
    }

    /// 1. NFKC (`precomposedStringWithCompatibilityMapping`), which unfolds ligatures (U+FB01 -> "fi").
    /// 2. Drop every scalar that is in joinerScalars.
    /// 3. lowercased().
    /// Returns "" when nothing is left.
    static func normalize(_ token: String) -> String {
        let composed = token.precomposedStringWithCompatibilityMapping
        var stripped = String.UnicodeScalarView()
        for scalar in composed.unicodeScalars where !joinerScalars.contains(scalar) {
            stripped.append(scalar)
        }
        return String(stripped).lowercased()
    }
}

/// FTS5 tokenizer `studyreader`: unicode61 (remove_diacritics 2, tokenchars = joiners) plus SearchTokenNormalizer.
final class SearchTokenizer: FTS5WrapperTokenizer {
    static let name = "studyreader"
    let wrappedTokenizer: any FTS5Tokenizer

    /// Ignores `arguments`.
    init(db: Database, arguments: [String]) throws {
        wrappedTokenizer = try db.makeTokenizer(Self.baseDescriptor)
    }

    static var baseDescriptor: FTS5TokenizerDescriptor {
        FTS5TokenizerDescriptor(components: [
            "unicode61", "remove_diacritics", "2", "tokenchars", SearchTokenNormalizer.tokenCharacters,
        ])
    }

    func accept(
        token: String,
        flags: FTS5TokenFlags,
        for tokenization: FTS5Tokenization,
        tokenCallback: FTS5WrapperTokenCallback
    ) throws {
        let normalized = SearchTokenNormalizer.normalize(token)
        guard !normalized.isEmpty else { return }
        try tokenCallback(normalized, flags)
    }
}
