import Foundation

enum ImportFailureReason: Sendable, Equatable {
    case damaged             // PDF can't be opened, Markdown isn't UTF-8 or can't be read
    case wrongPassword
    case passwordCancelled
    case declinedLargeFile
    case copyFailed          // file system or database error while storing
}

struct ImportedDocument: Sendable, Equatable {
    var documentId: String
    var title: String
}

struct ImportFailure: Sendable, Equatable {
    var fileName: String
    var reason: ImportFailureReason
}

/// What an import batch did, for the UI to show (SPEC F-02, F-03).
struct ImportReport: Sendable, Equatable {
    var imported: [ImportedDocument] = []
    var duplicates: [String] = []              // titles of the existing documents
    var unsupported: [String] = []             // file names (top-level items only)
    var failures: [ImportFailure] = []
    var unreadableImageCount: Int = 0
    var missingImageCount: Int = 0             // informational, not in the summary

    /// User text, lines joined with "\n": the import count (only when something was imported or skipped as
    /// unsupported), one line per duplicate, one per failure, then the unreadable-image line.
    var summary: String {
        var lines: [String] = []
        if !imported.isEmpty || !unsupported.isEmpty {
            var line = "Imported \(imported.count)"
            if !unsupported.isEmpty {
                line += ", skipped \(unsupported.count) (unsupported type)"
            }
            lines.append(line)
        }
        for title in duplicates {
            lines.append("Already in library: \(title)")
        }
        for failure in failures {
            switch failure.reason {
            case .damaged: lines.append("Couldn't open \(failure.fileName)")
            case .wrongPassword: lines.append("Wrong password for \(failure.fileName)")
            case .passwordCancelled: lines.append("Skipped \(failure.fileName) (password required)")
            case .declinedLargeFile: lines.append("Skipped \(failure.fileName) (larger than 500 MB)")
            case .copyFailed: lines.append("Couldn't import \(failure.fileName)")
            }
        }
        if unreadableImageCount == 1 {
            lines.append("1 image couldn't be read and shows as a placeholder.")
        } else if unreadableImageCount > 1 {
            lines.append("\(unreadableImageCount) images couldn't be read and show as placeholders.")
        }
        return lines.joined(separator: "\n")
    }
}
