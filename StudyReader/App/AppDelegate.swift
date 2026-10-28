import AppKit

/// Receives files opened through the Dock icon or Finder's "Open With" (SPEC F-02) and passes them to
/// `ExternalURLRouter.shared`, which buffers them until the library window attaches its handler.
/// Other URLs (Google's sign-in redirect) go to `GoogleSignInAuth`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        var files: [URL] = []
        for url in urls {
            if url.isFileURL {
                files.append(url)
            } else {
                _ = GoogleSignInAuth.handle(url)
            }
        }
        if !files.isEmpty {
            ExternalURLRouter.shared.receive(files)
        }
    }
}
