import XCTest

private typealias Sample = StudyReaderUI.Sample

/// T63, T82, T86, SPEC F-09: the Notes tab of the reader inspector.
final class NotesTabTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    private func showNotes(_ ui: StudyReaderUI) {
        if !ui.isInspectorOpen {
            ui.inspectorToggle.click()
            _ = ui.waitUntil { ui.isInspectorOpen }
        }
        ui.app.radioButtons["Notes"].click()
        ui.settle(0.5)
    }

    @MainActor
    private func value(of editor: XCUIElement) -> String {
        editor.value as? String ?? ""
    }

    /// C17
    @MainActor
    func testNotesTabKeepsTextAcrossTabSwitchAndReopen() {
        let ui = StudyReaderUI.launch()
        ui.openDocument(Sample.lecture)
        showNotes(ui)
        let editor = ui.app.textViews["Document note"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "No Document note editor.")
        ui.attachHierarchy("Notes tab hierarchy", to: self)
        editor.click()
        XCTAssertTrue(ui.hasKeyboardFocus(editor), "The note editor doesn't hold keyboard focus after the click.")
        editor.typeText("Remember cristae")
        ui.settle(1.5)

        ui.app.radioButtons["Highlights"].click()
        ui.settle(0.5)
        ui.app.radioButtons["Notes"].click()
        XCTAssertTrue(
            ui.waitUntil { self.value(of: ui.app.textViews["Document note"]).contains("Remember cristae") },
            "The note text was lost after switching tabs: '\(value(of: ui.app.textViews["Document note"]))'."
        )

        ui.closeFrontTab()
        XCTAssertTrue(ui.card(Sample.lecture).waitForExistence(timeout: 10), "The library didn't come back after closing the tab.")
        ui.openDocument(Sample.lecture)
        showNotes(ui)
        XCTAssertTrue(
            ui.waitUntil { self.value(of: ui.app.textViews["Document note"]).contains("Remember cristae") },
            "The note text wasn't restored after reopening: '\(value(of: ui.app.textViews["Document note"]))'."
        )
    }

    /// C18 (and T86: headings, lists and tags in the preview)
    @MainActor
    func testPreviewRendersHeadingsListsAndTags() {
        let ui = StudyReaderUI.launch()
        ui.openDocument(Sample.lecture)
        showNotes(ui)
        let editor = ui.app.textViews["Document note"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "No Document note editor.")
        editor.click()
        XCTAssertTrue(ui.hasKeyboardFocus(editor), "The note editor doesn't hold keyboard focus after the click.")
        editor.typeText("# Plan\n#todo check\n\n- a\n- b\n\n1. one\n2. two")
        ui.settle(1)

        ui.app.checkBoxes["Preview"].click()
        XCTAssertTrue(ui.staticText("Plan").waitForExistence(timeout: 5), "The heading 'Plan' isn't rendered.")
        XCTAssertTrue(ui.staticText(containing: "#todo check").exists, "The tag line '#todo check' isn't shown.")
        XCTAssertTrue(ui.staticText("• a").exists, "No bullet '• a'.")
        XCTAssertTrue(ui.staticText("• b").exists, "No bullet '• b'.")
        XCTAssertTrue(ui.staticText("1. one").exists, "No numbered item '1. one'.")
        XCTAssertTrue(ui.staticText("2. two").exists, "No numbered item '2. two'.")
        XCTAssertFalse(ui.staticText("# Plan").exists, "The heading is shown as raw '# Plan'.")
        ui.attachHierarchy("Notes preview hierarchy", to: self)
        ui.attachScreenshot("Notes preview", to: self)

        ui.app.checkBoxes["Preview"].click()
        let source = ui.app.textViews["Document note"]
        XCTAssertTrue(source.waitForExistence(timeout: 5), "The editor didn't come back after unticking Preview.")
        XCTAssertTrue(value(of: source).contains("# Plan"), "The editor lost the raw text: '\(value(of: source))'.")

        source.click()
        source.typeKey("a", modifierFlags: .command)
        source.typeKey(.delete, modifierFlags: [])
        ui.settle(0.5)
        ui.app.checkBoxes["Preview"].click()
        XCTAssertTrue(ui.staticText("No notes yet.").waitForExistence(timeout: 5), "The empty note doesn't show 'No notes yet.'.")
    }
}
