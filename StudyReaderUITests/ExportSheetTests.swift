import XCTest

private typealias Sample = StudyReaderUI.Sample

/// T73: the Export sheet. The in-memory library has no Google credentials, so the sheet shows the
/// "not configured" state and never makes a request.
final class ExportSheetTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// File > Export Highlights… (⇧⌘E) opens the sheet with no selection, and Cancel closes it.
    @MainActor
    func testShortcutOpensTheSheetAndCancelClosesIt() {
        let ui = StudyReaderUI.launch()
        XCTAssertTrue(ui.menuItemState("File", "Export Highlights…").exists)
        ui.app.typeKey("e", modifierFlags: [.command, .shift])
        let sheet = ui.sheet
        XCTAssertTrue(sheet.buttons["Cancel"].waitForExistence(timeout: 5), "⇧⌘E didn't open the Export sheet.")
        sheet.buttons["Cancel"].click()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3), "Cancel didn't close the Export sheet.")
    }

    /// Not configured: the sheet says so and has no Export button.
    @MainActor
    func testNotConfiguredShowsMessageInsteadOfExportButton() {
        let ui = StudyReaderUI.launch()
        ui.app.typeKey("e", modifierFlags: [.command, .shift])
        let sheet = ui.sheet
        XCTAssertTrue(sheet.buttons["Cancel"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            sheet.staticTexts["Google export not configured"].waitForExistence(timeout: 3),
            "The sheet doesn't say that Google export isn't configured."
        )
        XCTAssertFalse(sheet.buttons["Export"].exists, "The Export button is shown without Google configured.")
        ui.attachScreenshot("T73 not configured", to: self)
        sheet.buttons["Cancel"].click()
    }

    /// The library context menu opens the sheet for that document.
    @MainActor
    func testContextMenuOpensTheSheet() {
        let ui = StudyReaderUI.launch()
        ui.card(Sample.lecture).rightClick()
        // The File menu has an "Export Highlights…" item too; the open context menu holds the one that's hittable.
        let contextItem = ui.app.menuItems.matching(identifier: "Export Highlights…").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(contextItem, "The context menu has no Export Highlights… item.")
        contextItem?.click()
        XCTAssertTrue(ui.sheet.buttons["Cancel"].waitForExistence(timeout: 5), "Context menu Export Highlights… didn't open the sheet.")
        ui.sheet.buttons["Cancel"].click()
    }
}
