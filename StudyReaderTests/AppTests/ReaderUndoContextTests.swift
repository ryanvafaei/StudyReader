import AppKit
import Testing
@testable import StudyReader

@MainActor
@Suite("ReaderUndoContext")
struct ReaderUndoContextTests {
    private static func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: true
        )
    }

    @Test
    func readerWindowWithoutEditableResponder() {
        let window = Self.makeWindow()
        window.isReleasedWhenClosed = false
        let plain = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.contentView?.addSubview(plain)
        let editor = NSTextView(frame: CGRect(x: 0, y: 100, width: 100, height: 100))
        editor.isEditable = true
        window.contentView?.addSubview(editor)

        #expect(AppCommands.isReaderUndoContext(nil) == false)

        // An unshown window in the unit-test host may report canBecomeMain == false, which makes the answer false
        // regardless of the responder; the "true" cases are only meaningful when the window can become main.
        let canBeMain = window.canBecomeMain

        window.makeFirstResponder(plain)
        if canBeMain {
            #expect(AppCommands.isReaderUndoContext(window) == true)
        }

        window.makeFirstResponder(editor)
        #expect(window.firstResponder === editor)
        #expect(AppCommands.isReaderUndoContext(window) == false)

        editor.isEditable = false
        if canBeMain {
            #expect(AppCommands.isReaderUndoContext(window) == true)
        }
    }

    @Test
    func sheetIsNotAReaderContext() {
        let parent = Self.makeWindow()
        parent.isReleasedWhenClosed = false
        let sheet = Self.makeWindow()
        sheet.isReleasedWhenClosed = false
        parent.beginSheet(sheet)
        // Whether the sheet attaches depends on the unit-test host having a window server; only assert when it did.
        if sheet.sheetParent != nil {
            #expect(AppCommands.isReaderUndoContext(sheet) == false)
        }
        parent.endSheet(sheet)
    }
}
