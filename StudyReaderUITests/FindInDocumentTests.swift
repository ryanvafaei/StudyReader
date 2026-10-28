import XCTest

private typealias Sample = StudyReaderUI.Sample

/// T67, SPEC F-04: the PDF find bar.
final class FindInDocumentTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    private func openLecture() -> StudyReaderUI {
        let ui = StudyReaderUI.launch()
        ui.openDocument(Sample.lecture)
        XCTAssertTrue(ui.app.toolbars.buttons["Find in Document"].waitForExistence(timeout: 10), "The reader toolbar didn't appear.")
        return ui
    }

    /// F1
    @MainActor
    func testPDFFindBarOpensFromShortcutToolbarAndMenu() {
        let ui = openLecture()
        ui.attachHierarchy("Reader hierarchy", to: self)

        ui.app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(ui.findField.waitForExistence(timeout: 5), "Command-F didn't show the find bar.")
        ui.attachScreenshot("PDF find bar", to: self)
        ui.app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(ui.findField.waitForNonExistence(timeout: 5), "Escape didn't hide the find bar.")

        ui.app.toolbars.buttons["Find in Document"].click()
        XCTAssertTrue(ui.findField.waitForExistence(timeout: 5), "The toolbar button didn't show the find bar.")
        ui.app.buttons["Close find bar"].click()
        XCTAssertTrue(ui.findField.waitForNonExistence(timeout: 5), "Close find bar didn't hide the find bar.")

        ui.menu("Edit", "Find in Document")
        XCTAssertTrue(ui.findField.waitForExistence(timeout: 5), "Edit > Find in Document didn't show the find bar.")
    }

    /// F2, plus B24 (2): Shift-Return steps back.
    @MainActor
    func testPDFFindCountsAndSteps() {
        let ui = openLecture()
        ui.app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(ui.findField.waitForExistence(timeout: 5))
        ui.settle()
        ui.findField.typeText("proteins")
        ui.settle()
        ui.attachHierarchy("Find bar hierarchy", to: self)

        var k = 0
        var n = 0
        let counted = ui.waitUntil(timeout: 10) {
            let parts = ui.matchCountText.components(separatedBy: " of ")
            guard parts.count == 2, let first = Int(parts[0]), let second = Int(parts[1]), second >= 2 else { return false }
            k = first
            n = second
            return true
        }
        XCTAssertTrue(counted, "The match count never reached 'k of N' with N >= 2; it shows '\(ui.matchCountText)'.")
        guard counted else { return }

        ui.findField.typeKey(.return, modifierFlags: [])
        let forward = "\(k % n + 1) of \(n)"
        XCTAssertTrue(ui.waitUntil { ui.matchCountText == forward }, "Return should show '\(forward)'; it shows '\(ui.matchCountText)'.")

        ui.findField.typeKey(.return, modifierFlags: .shift)
        let back = "\(k) of \(n)"
        XCTAssertTrue(ui.waitUntil { ui.matchCountText == back }, "Shift-Return should show '\(back)'; it shows '\(ui.matchCountText)'.")

        for _ in 0..<n {
            ui.findField.typeKey(.return, modifierFlags: [])
            ui.settle(0.3)
        }
        XCTAssertTrue(ui.waitUntil { ui.matchCountText == back }, "\(n) Returns should wrap to '\(back)'; it shows '\(ui.matchCountText)'.")
    }

    /// F3
    @MainActor
    func testPDFFindWithNoMatchesDisablesTheArrows() {
        let ui = openLecture()
        ui.app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(ui.findField.waitForExistence(timeout: 5))
        ui.settle()
        ui.findField.typeText("zzqxv")
        XCTAssertTrue(ui.waitUntil(timeout: 10) { ui.matchCountText == "No matches" }, "The match count shows '\(ui.matchCountText)'.")
        let previous = ui.app.buttons["Previous match"]
        let next = ui.app.buttons["Next match"]
        XCTAssertTrue(previous.exists, "No Previous match button.")
        XCTAssertTrue(next.exists, "No Next match button.")
        XCTAssertFalse(previous.isEnabled, "Previous match is enabled with no matches.")
        XCTAssertFalse(next.isEnabled, "Next match is enabled with no matches.")
    }
}
