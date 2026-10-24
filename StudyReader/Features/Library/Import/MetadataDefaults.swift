import Foundation

/// Title and author defaults for imported documents (SPEC F-11).
enum MetadataDefaults {
    private static let fileNameExtensions = [
        ".pdf", ".doc", ".docx", ".ppt", ".pptx", ".key", ".pages",
        ".tex", ".dvi", ".txt", ".md", ".markdown",
    ]
    private static let placeholderTitles: Set<String> = [
        "untitled", "untitled document", "document", "presentation", "powerpoint presentation",
    ]
    private static let placeholderPrefixes = ["microsoft word - ", "microsoft powerpoint - "]

    /// The trimmed metadata title, unless it looks like a file name or a placeholder. Otherwise the file name
    /// without its last extension (or the whole name when that is empty).
    static func title(metadataTitle: String?, fileName: String) -> String {
        if let metadataTitle {
            let trimmed = metadataTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !isFileNameLike(trimmed) {
                return trimmed
            }
        }
        return nameWithoutLastExtension(fileName)
    }

    /// The trimmed metadata author, or "".
    static func author(metadataAuthor: String?) -> String {
        metadataAuthor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// `trimmed` is already trimmed.
    private static func isFileNameLike(_ trimmed: String) -> Bool {
        if trimmed.isEmpty { return true }
        let lowercased = trimmed.lowercased()
        if fileNameExtensions.contains(where: { lowercased.hasSuffix($0) }) { return true }
        if trimmed.contains("/") || trimmed.contains("\\") { return true }
        if !trimmed.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) { return true }
        if placeholderTitles.contains(lowercased) { return true }
        return placeholderPrefixes.contains(where: { lowercased.hasPrefix($0) })
    }

    /// "Lecture 3.PDF" → "Lecture 3"; "README" → "README"; ".pdf" → ".pdf".
    private static func nameWithoutLastExtension(_ fileName: String) -> String {
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return fileName }
        let base = String(fileName[..<dot])
        return base.isEmpty ? fileName : base
    }
}
