import XCTest

/// T52j U6: Settings > General > Highlight colors shows each colour's name and fits the window.
final class SettingsTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// Every row shows the colour name on the left and an editable label on the right; nothing is cut off.
    @MainActor
    func testHighlightColorRowsShowColourNamesAndFitTheWindow() {
        let ui = StudyReaderUI.launch(seed: false)
        ui.settle()
        ui.app.typeKey(",", modifierFlags: .command)

        let window = ui.app.windows.matching(
            NSPredicate(format: "identifier == 'com_apple_SwiftUI_Settings_window' OR title == 'General'")
        ).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Settings didn't open with ⌘,.")
        let generalTab = window.toolbars.buttons["General"]
        if generalTab.exists {
            generalTab.click()
        }

        for name in ["Yellow", "Green", "Blue", "Pink", "Purple"] {
            XCTAssertTrue(window.staticTexts[name].waitForExistence(timeout: 3), "The row for \(name) shows no colour name.")
        }
        let placeholders = window.staticTexts.matching(
            NSPredicate(format: "label == 'Label' OR value == 'Label'")
        )
        XCTAssertEqual(placeholders.count, 0, "A colour row still shows the placeholder 'Label' instead of its name.")

        // XCUITest exposes each field's label combined with its accessibility label ("Label, Label for purple highlights"),
        // so match by substring rather than exact equality.
        for name in ["yellow", "green", "blue", "pink", "purple"] {
            let field = window.textFields.matching(
                NSPredicate(format: "label CONTAINS %@", "Label for \(name) highlights")
            ).firstMatch
            XCTAssertTrue(field.exists, "The label field for \(name) highlights is missing.")
            XCTAssertTrue(window.frame.contains(field.frame), "The \(name) colour row is cut off at the edge of the window.")
        }
        ui.attachScreenshot("Settings General", to: self)

        ui.app.typeKey("w", modifierFlags: .command)
    }

    /// B35(2): Settings opens with no colour-label field holding keyboard focus (so typing can't edit a label by accident).
    @MainActor
    func testSettingsOpensWithoutAFocusedLabelField() {
        let ui = StudyReaderUI.launch(seed: false)
        ui.settle()
        ui.app.typeKey(",", modifierFlags: .command)

        let window = ui.app.windows.matching(
            NSPredicate(format: "identifier == 'com_apple_SwiftUI_Settings_window' OR title == 'General'")
        ).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Settings didn't open with ⌘,.")
        ui.settle()

        let fields = window.textFields.matching(NSPredicate(format: "label CONTAINS 'Label for'"))
        XCTAssertGreaterThanOrEqual(fields.count, 5, "The colour label fields are missing.")
        for index in 0..<fields.count {
            let field = fields.element(boundBy: index)
            XCTAssertFalse(ui.hasKeyboardFocus(field), "A label field has keyboard focus on open: \(field.label)")
        }

        ui.app.typeKey("w", modifierFlags: .command)
    }
}
