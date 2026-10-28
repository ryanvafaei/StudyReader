import AppKit

/// Receives files opened through the Dock icon or Finder's "Open With" (SPEC F-02) and passes them to
/// `ExternalURLRouter.shared`, which buffers them until the library window attaches its handler.
/// Other URLs (Google's sign-in redirect) go to `GoogleSignInAuth`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        let routes = ExternalURLRouter.split(urls)
        for url in routes.redirects {
            _ = GoogleSignInAuth.handle(url)
        }
        ExternalURLRouter.shared.receive(routes.files)
    }
}
