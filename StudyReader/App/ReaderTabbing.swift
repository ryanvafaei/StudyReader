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
    ///
    /// The window takes the group's frame first, so tabbing it in doesn't resize the group (T52b F1). The tabbing
    /// itself runs on the next main-actor turn, after SwiftUI has laid out the new window.
    static func joinMainTabGroup(_ window: NSWindow) {
        configure(window)
        observeWindows()
        guard let anchor = anchorWindow(excluding: window) else { return }
        let groupFrame = anchor.frame
        if anchor === mainWindow, (anchor.tabGroup?.windows ?? [anchor]).allSatisfy({ $0 === anchor || $0 === window }) {
            libraryFrameWithReaders = groupFrame
        }
        window.setFrame(groupFrame, display: false)
        Task { @MainActor in
            let group = anchor.tabGroup?.windows ?? [anchor]
            if !group.contains(where: { $0 === window }) {
                let last = group.last ?? anchor
                last.addTabbedWindow(window, ordered: .above)
            }
            if window.frame != groupFrame {
                window.setFrame(groupFrame, display: true)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// A reader window without a document (the tab bar's "+", or restoration without a value) is closed on the
    /// next main-actor turn and the library tab is brought forward. No empty "No document" tab stays open.
    static func discardEmptyWindow(_ window: NSWindow) {
        Task { @MainActor in
            window.close()
            mainWindow?.makeKeyAndOrderFront(nil)
        }
    }

    /// Registered once, by the first `joinMainTabGroup`. Kept alive for the app's lifetime.
    private static var windowObserver: ReaderWindowObserver?

    /// The library's frame to put back when the last reader tab closes (T52b F1). Set when the first reader joins, and
    /// kept current afterwards: a user resize or move of the library or its group updates it while readers are open.
    /// Nil when nothing is pending (no readers, or the library has closed).
    private static var libraryFrameWithReaders: NSRect?

    private static func observeWindows() {
        guard windowObserver == nil else { return }
        windowObserver = ReaderWindowObserver()
    }

    /// Called as a window is about to close. Closing the library forgets the stored frame. When the last reader tab of
    /// the library's group closes, AppKit re-fits the library window (T52b F1: it ended up 10 pt taller than before the
    /// reader opened), so the library goes back to the frame kept while the readers were open. The restore runs on the
    /// next main-actor turn, after AppKit has removed the tab.
    ///
    /// The group check is "no windows other than the library and the closing one", not "the closing window is in the
    /// group": AppKit has already taken a closing tab out of the group by the time `willClose` is posted (T52b, CI: a
    /// membership check here skipped the restore). A reader moved out to its own window before closing therefore also
    /// passes, and restores nothing new: the stored frame is kept equal to the library's latest user frame.
    static func readerWindowWillClose(_ closing: NSWindow) {
        guard let library = mainWindow else { return }
        if closing === library {
            libraryFrameWithReaders = nil
            return
        }
        guard closing.tabbingIdentifier == identifier, library.isVisible else { return }
        let group = library.tabGroup?.windows ?? [library]
        guard group.allSatisfy({ $0 === library || $0 === closing }),
              let target = libraryFrameWithReaders
        else { return }
        libraryFrameWithReaders = nil
        Task { @MainActor in
            guard library.isVisible, library.frame != target else { return }
            library.setFrame(target, display: true)
        }
    }

    /// Called when a window finishes a user resize (a drag of its edge or corner).
    static func windowDidEndLiveResize(_ window: NSWindow) {
        keepLibraryFrameCurrent(from: window)
    }

    /// Called when a window moves. Only a move with a mouse button held counts as the user's: AppKit's own re-fit of the
    /// library when a tab closes is not a user change and must not overwrite the stored frame.
    static func windowDidMove(_ window: NSWindow) {
        guard NSEvent.pressedMouseButtons != 0 else { return }
        keepLibraryFrameCurrent(from: window)
    }

    /// Stores the library's current frame, if readers are open and `window` is the library or in its tab group. Tabs
    /// share one frame, so the library's frame is the group's.
    private static func keepLibraryFrameCurrent(from window: NSWindow) {
        guard libraryFrameWithReaders != nil, let library = mainWindow, library.isVisible else { return }
        let group = library.tabGroup?.windows ?? [library]
        guard group.contains(where: { $0 === window }) else { return }
        libraryFrameWithReaders = library.frame
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

/// Watches the window notifications behind the library's frame for the reader tabs (T52b F1). Closing any window calls
/// `ReaderTabbing.readerWindowWillClose`; a finished user resize or a move calls the matching handler. A programmatic
/// `setFrame` by AppKit or by the app doesn't produce a user resize or a move with a mouse button held, so it isn't
/// recorded.
///
/// Selector-based on purpose: a closure-based observer would send the non-Sendable `Notification` across isolation.
@MainActor
final class ReaderWindowObserver: NSObject {
    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowDidEndLiveResize(_:)),
            name: NSWindow.didEndLiveResizeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: nil
        )
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        ReaderTabbing.readerWindowWillClose(window)
    }

    @objc private func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        ReaderTabbing.windowDidEndLiveResize(window)
    }

    @objc private func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        ReaderTabbing.windowDidMove(window)
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
