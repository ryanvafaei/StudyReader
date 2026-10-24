import Foundation
import Markdown

/// Stored file names for Markdown image sources (ADR-0016). The renderer computes the same names.
enum MarkdownImageNaming {
    /// Stored file name for an image source written in Markdown, or nil when the source isn't copied: it has a
    /// URL scheme, starts with "/" or "#", is empty, or its lowercased path extension (query and fragment removed)
    /// isn't 1–10 characters of a–z/0–9. Name = first 16 hex characters of SHA-256 of `source` + "." + extension.
    static func storedFileName(forSource source: String) -> String? {
        if source.isEmpty || source.contains("://") || source.hasPrefix("data:")
            || source.hasPrefix("mailto:") || source.hasPrefix("/") || source.hasPrefix("#") {
            return nil
        }
        let path = source.prefix { $0 != "?" && $0 != "#" }
        let lastComponent = path.split(separator: "/", omittingEmptySubsequences: false).last ?? ""
        guard let dot = lastComponent.lastIndex(of: ".") else { return nil }
        let fileExtension = lastComponent[lastComponent.index(after: dot)...].lowercased()
        let bytes = fileExtension.utf8
        let isValid = (1...10).contains(bytes.count) && bytes.allSatisfy { byte in
            (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
                || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
        }
        guard isValid else { return nil }
        let prefix = Hashing.sha256Hex(of: source).prefix(16)
        return "\(prefix).\(fileExtension)"
    }

    /// true for http/https sources. They render as a placeholder showing the URL and are never fetched.
    static func isRemote(_ source: String) -> Bool {
        let lowercased = source.lowercased()
        return lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://")
    }
}

/// Finds and copies the relative images a Markdown body refers to (ADR-0016).
enum MarkdownImageCollector {
    /// Image sources (swift-markdown `Image.source`) in document order, without duplicates.
    static func imageSources(in markdownBody: String) -> [String] {
        var walker = ImageSourceWalker()
        walker.visit(Document(parsing: markdownBody))
        var seen = Set<String>()
        return walker.sources.filter { seen.insert($0).inserted }
    }

    struct CopyResult: Sendable, Equatable {
        var copied: Int
        var missing: Int        // the copy failed with CocoaError .fileReadNoSuchFile or .fileNoSuchFile
        var unreadable: Int     // the copy failed with any other error (in practice the sandbox denying access)
        var alreadyPresent: Int // destination existed already (skipped; counts as copied for the caller)
    }

    /// For each source with a storedFileName: resolve `sourceFolder.appending(path: source.removingPercentEncoding ?? source)`,
    /// copy to imagesFolder/storedFileName (creating imagesFolder when the first copy happens). If the destination
    /// already exists, count alreadyPresent and skip (so a second call after folder access only retries the failures).
    /// Failures are classified by the thrown error, never with fileExists. Remote and invalid sources are skipped.
    static func copyImages(sources: [String], from sourceFolder: URL, to imagesFolder: URL) -> CopyResult {
        var result = CopyResult(copied: 0, missing: 0, unreadable: 0, alreadyPresent: 0)
        let fileManager = FileManager.default
        for source in sources {
            guard let storedName = MarkdownImageNaming.storedFileName(forSource: source) else { continue }
            let destination = imagesFolder.appending(path: storedName, directoryHint: .notDirectory)
            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                result.alreadyPresent += 1
                continue
            }
            let original = sourceFolder.appending(
                path: source.removingPercentEncoding ?? source,
                directoryHint: .notDirectory
            )
            do {
                try fileManager.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
                try fileManager.copyItem(at: original, to: destination)
                result.copied += 1
            } catch {
                if isNoSuchFile(error) {
                    result.missing += 1
                } else {
                    result.unreadable += 1
                }
            }
        }
        return result
    }

    private static func isNoSuchFile(_ error: Error) -> Bool {
        guard let cocoaError = error as? CocoaError else { return false }
        return cocoaError.code == .fileReadNoSuchFile || cocoaError.code == .fileNoSuchFile
    }
}

/// Collects `Image.source` values in document order.
private struct ImageSourceWalker: MarkupWalker {
    var sources: [String] = []

    mutating func visitImage(_ image: Image) {
        if let source = image.source {
            sources.append(source)
        }
        descendInto(image)
    }
}
