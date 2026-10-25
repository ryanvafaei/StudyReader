import AppKit
import SwiftUI

/// Native window tabbing for the main window and reader windows (ADR-0017, SPEC F-01). No custom tab bar: macOS draws
/// the tabs, and the user can drag tabs out or merge them as usual.
@MainActor
enum ReaderTabbing {
    static let identifier = "StudyReaderMain"

    /// The library window. Set by `configureMain`, held weakly so a closed window isn't kept alive.
    private(set) static weak var mainWindow: NSWindow?

    /// Makes `window` a preferred tab of the StudyReader tab group.
    static func configure(_ window: NSWindow) {
        window.tabbingMode = .preferred
        window.tabbingIdentifier = identifier
    }

    /// `configure` for the library window, which becomes the first tab of the group and the anchor reader tabs join.
    static func configureMain(_ window: NSWindow) {
        configure(window)
        mainWindow = window
    }

    /// Configures `window`, then adds it after the last tab of the main window's group and selects it. A window that is
    /// already in the group is left where it is. Without a visible main window nothing is joined.
    static func joinMainTabGroup(_ window: NSWindow) {
        configure(window)
        guard let anchor = anchorWindow(excluding: window) else { return }
        let group = anchor.tabGroup?.windows ?? [anchor]
        guard !group.contains(where: { $0 === window }) else { return }
        let last = group.last ?? anchor
        last.addTabbedWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
    }

    /// The main window when it's open, otherwise the first other visible StudyReader window.
    private static func anchorWindow(excluding window: NSWindow) -> NSWindow? {
        if let mainWindow, mainWindow !== window, mainWindow.isVisible {
            return mainWindow
        }
        return NSApp.windows.first { candidate in
            candidate !== window && candidate.isVisible && candidate.tabbingIdentifier == identifier
        }
    }
}

/// Zero-size view that reports the hosting window once, from `viewDidMoveToWindow` (SwiftUI can't reach NSWindow).
struct WindowAccessor: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowAccessorView {
        WindowAccessorView(onWindow: onWindow)
    }

    func updateNSView(_ nsView: WindowAccessorView, context: Context) {
        nsView.onWindow = onWindow
    }
}

@MainActor
final class WindowAccessorView: NSView {
    var onWindow: @MainActor (NSWindow) -> Void
    private var hasReported = false

    init(onWindow: @escaping @MainActor (NSWindow) -> Void) {
        self.onWindow = onWindow
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("WindowAccessorView is created in code only.")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !hasReported, let window else { return }
        hasReported = true
        onWindow(window)
    }
}
