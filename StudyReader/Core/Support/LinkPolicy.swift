import Foundation

/// The app's only link-scheme filter (SPEC F-03): links from imported documents and notes open outside the app only
/// for these schemes; every other link does nothing.
enum LinkPolicy {
    static let openableSchemes: Set<String> = ["http", "https", "mailto"]

    /// Case-insensitive scheme check; false when the URL has no scheme.
    static func isOpenable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return openableSchemes.contains(scheme)
    }
}
