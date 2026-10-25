import AppKit

/// Receives files opened through the Dock icon or Finder's "Open With" (SPEC F-02) and passes them to
/// `ExternalURLRouter.shared`, which buffers them until the library window attaches its handler.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        ExternalURLRouter.shared.receive(urls)
    }
}
