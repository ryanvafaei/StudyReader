import AppKit
import Testing
@testable import StudyReader

@Suite("ReaderTabbing")
@MainActor
struct ReaderTabbingTests {
    @Test func configureSetsPreferredTabbing() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )

        ReaderTabbing.configure(window)

        #expect(window.tabbingMode == .preferred)
        #expect(window.tabbingIdentifier == "StudyReaderMain")
    }

    @Test func joinChangesNoFrameSynchronously() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let frameBefore = window.frame

        ReaderTabbing.joinMainTabGroup(window)

        // Frame, tab and ordering changes are deferred to the next main-actor turn (T52h); only the property is set now.
        #expect(window.frame == frameBefore)
        #expect(window.tabbingIdentifier == "StudyReaderMain")
    }

    @Test func joinConfiguresEvenWithoutGroup() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )

        ReaderTabbing.joinMainTabGroup(window)

        #expect(window.tabbingMode == .preferred)
        #expect(window.tabbingIdentifier == "StudyReaderMain")
        // The test host may already have a visible main window to join; either way the window is in at most one group.
        let windows = window.tabGroup?.windows ?? [window]
        #expect(windows.filter { $0 === window }.count == 1)
    }
}
