/// Search test strings as Unicode escapes (ADR-0014). Never retype these as literal characters.
enum SearchSamples {
    /// "photo\u{00AD}synthesis": a soft hyphen U+00AD after "photo", as PDFs store hyphenation points (15 UTF-16 units)
    static let photosynthesisSoftHyphen = "photo\u{00AD}synthesis"
    /// "photosynthesis" as typed (14 UTF-16 units)
    static let photosynthesisPlain = "photosynthesis"
    /// "photos", a prefix of photosynthesisPlain
    static let photosynthesisPrefix = "photos"
    /// "ﬁnd" with U+FB01 LATIN SMALL LIGATURE FI, common in PDF text extraction (3 UTF-16 units)
    static let findLigature = "\u{FB01}nd"
    /// "ﬂow" with U+FB02 LATIN SMALL LIGATURE FL (3 UTF-16 units)
    static let flowLigature = "\u{FB02}ow"
    /// "résumé" decomposed (NFD): "e" + U+0301 combining acute (8 UTF-16 units)
    static let resumeDecomposed = "re\u{0301}sume\u{0301}"
    /// "Résumé" precomposed with U+00E9 and a capital R (6 UTF-16 units)
    static let resumeCapitalPrecomposed = "R\u{00E9}sum\u{00E9}"
    /// "Núñez" precomposed with U+00FA and U+00F1 (5 UTF-16 units)
    static let authorWithDiacritics = "N\u{00FA}\u{00F1}ez"
}
