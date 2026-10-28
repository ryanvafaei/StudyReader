import XCTest

private typealias Sample = StudyReaderUI.Sample

/// T69 checkpoint, sidebar Highlights section (F-13 without Similar and Mastery).
final class HighlightsBrowserTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func rows(in ui: StudyReaderUI) -> XCUIElementQuery {
        ui.app.descendants(matching: .any).matching(identifier: "highlight-row")
    }

    /// Opening the section lists the seeded highlights.
    @MainActor
    func testSectionListsHighlights() {
        let ui = StudyReaderUI.launch()
        ui.showSection("Highlights")
        XCTAssertTrue(rows(in: ui).firstMatch.waitForExistence(timeout: 8), "No highlight rows in the browser.")
        XCTAssertGreaterThanOrEqual(rows(in: ui).count, 2)
        ui.attachScreenshot("Highlights browser", to: self)
    }

    /// An empty library shows the empty state.
    @MainActor
    func testEmptyStateWithoutHighlights() {
        let ui = StudyReaderUI.launch(seed: false)
        ui.showSection("Highlights")
        XCTAssertTrue(ui.app.staticTexts["No highlights yet"].waitForExistence(timeout: 5))
    }

    /// A color filter narrows the list, and Clear brings it back.
    @MainActor
    func testColorFilterNarrowsTheListAndClearRestoresIt() {
        let ui = StudyReaderUI.launch()
        ui.showSection("Highlights")
        XCTAssertTrue(rows(in: ui).firstMatch.waitForExistence(timeout: 8))
        let total = rows(in: ui).count

        let yellow = ui.app.buttons["Filter by Yellow"]
        XCTAssertTrue(yellow.waitForExistence(timeout: 3), "No color filter button.")
        yellow.click()
        XCTAssertTrue(
            ui.waitUntil { self.rows(in: ui).count < total },
            "The Yellow filter didn't narrow the list (still \(total) rows)."
        )
        ui.attachScreenshot("Yellow filter", to: self)

        ui.app.buttons["Clear filters"].firstMatch.click()
        XCTAssertTrue(ui.waitUntil { self.rows(in: ui).count == total }, "Clear didn't restore the list.")
    }

    /// Selecting a row shows the detail pane with its note and "Open in Document".
    @MainActor
    func testSelectingARowShowsTheDetailPane() {
        let ui = StudyReaderUI.launch()
        ui.showSection("Highlights")
        let first = rows(in: ui).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        first.click()
        XCTAssertTrue(ui.app.buttons["Open in Document"].waitForExistence(timeout: 5), "No detail pane after selecting a row.")
        XCTAssertTrue(ui.app.descendants(matching: .any)["Note"].exists)
    }

    /// Return and Escape typed in the browser's note field must not reach the library's hidden buttons: no document
    /// opens, the selection stays and the list is unchanged (LibraryView isn't mounted here).
    @MainActor
    func testReturnAndEscapeDoNothingToTheLibrary() {
        let ui = StudyReaderUI.launch()
        ui.showSection("Highlights")
        let first = rows(in: ui).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        let total = rows(in: ui).count
        first.click()
        let open = ui.app.buttons["Open in Document"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), "No detail pane after selecting a row.")
        let note = ui.app.descendants(matching: .any)["Note"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5), "No note field in the detail pane.")
        note.click()
        let windows = ui.app.windows.count

        ui.app.typeKey(.return, modifierFlags: [])
        ui.settle(1)
        ui.app.typeKey(.escape, modifierFlags: [])
        ui.settle(1)

        XCTAssertEqual(ui.app.windows.count, windows, "Return or Escape opened or closed a window.")
        XCTAssertFalse(ui.card(Sample.lecture).exists, "The library appeared after Return or Escape.")
        XCTAssertEqual(rows(in: ui).count, total, "The browser list changed after Return or Escape.")
        XCTAssertTrue(open.exists, "The row was deselected by Return or Escape (the detail pane is gone).")
    }
}
