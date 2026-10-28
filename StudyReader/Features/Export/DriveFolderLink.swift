import Foundation

/// Parses a pasted Google Drive folder link into a folder ID.
enum DriveFolderLink {
    /// Folder ID from `https://drive.google.com/drive/folders/<ID>`, `…/drive/u/<n>/folders/<ID>` (with or without a
    /// query string), `https://drive.google.com/open?id=<ID>`, or a bare ID (`^[A-Za-z0-9_-]{10,}$`). Trimmed. Else nil.
    static func folderId(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if isValidId(trimmed) { return trimmed }

        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "drive.google.com" else {
            return nil
        }

        let segments = components.path.split(separator: "/").map(String.init)
        if segments.first == "drive" {
            var rest = segments.dropFirst()
            if rest.first == "u", rest.count >= 2, rest[rest.startIndex + 1].allSatisfy(\.isNumber) {
                rest = rest.dropFirst(2)
            }
            if rest.first == "folders", rest.count >= 2 {
                let id = rest[rest.startIndex + 1]
                return isValidId(id) ? id : nil
            }
            return nil
        }
        if segments == ["open"],
           let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
           isValidId(id) {
            return id
        }
        return nil
    }

    private static func isValidId(_ value: String) -> Bool {
        value.utf8.count >= 10 && value.utf8.allSatisfy { byte in
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
                || byte == 0x5F || byte == 0x2D
        }
    }
}
