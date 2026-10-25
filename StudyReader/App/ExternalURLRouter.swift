import Foundation

/// Routes files that arrive from outside the window (Dock drops, Finder "Open With") to the library's import
/// handler (SPEC F-02). URLs that arrive before a handler is attached are kept in order and handed over by
/// `attach(_:)`. The handler stays attached after the window closes, so later URLs still import.
@MainActor
final class ExternalURLRouter {
    /// The router shared by AppDelegate (producer) and RootView (consumer).
    static let shared = ExternalURLRouter()

    private(set) var pendingURLs: [URL] = []
    private var handler: (@MainActor ([URL]) -> Void)?

    /// Sets the handler, then hands over every URL buffered so far, in arrival order. The buffer is cleared first,
    /// so a second `attach` never delivers the same URLs twice.
    func attach(_ handler: @escaping @MainActor ([URL]) -> Void) {
        self.handler = handler
        let urls = pendingURLs
        pendingURLs = []
        if !urls.isEmpty {
            handler(urls)
        }
    }

    /// Delivers the URLs to the attached handler, or buffers them until one is attached. Empty input is ignored.
    func receive(_ urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }
        if let handler {
            handler(urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }
}
