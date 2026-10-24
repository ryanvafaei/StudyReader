import Foundation

/// Reads `#tag` names from note text (SPEC F-10). Pure: no storage, no I/O.
enum TagParsing {
    /// Longest allowed tag name, in Characters.
    private static let nameLimit = 40

    /// Tag names written as `#name` in `text`, in order of first appearance. Duplicates are removed
    /// case-insensitively; the first spelling is kept.
    ///
    /// - "#" must be at the start of the text or follow whitespace or "(".
    /// - The name is the longest run of letters, digits, "_" or "-" after "#". It must be 1 to 40 Characters, or it is ignored.
    /// - "# heading", "##x" and "a#b" give nothing.
    /// - Text inside a matched pair of backticks is ignored. An unmatched backtick is ordinary text.
    static func hashTags(in text: String) -> [String] {
        let characters = Array(text)
        var names: [String] = []
        var seen = Set<String>()
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "`", let closing = characters[(index + 1)...].firstIndex(of: "`") {
                index = closing + 1
                continue
            }
            guard character == "#", startsTag(characters, at: index) else {
                index += 1
                continue
            }
            var end = index + 1
            while end < characters.count, isNameCharacter(characters[end]) {
                end += 1
            }
            let length = end - (index + 1)
            if (1...nameLimit).contains(length) {
                let name = String(characters[(index + 1)..<end])
                if seen.insert(name.lowercased()).inserted {
                    names.append(name)
                }
            }
            index = end
        }
        return names
    }

    /// true when the "#" at `index` begins at the start of the text, or follows whitespace or "(".
    private static func startsTag(_ characters: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1]
        return previous.isWhitespace || previous == "("
    }

    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isWholeNumber || character == "_" || character == "-"
    }
}
