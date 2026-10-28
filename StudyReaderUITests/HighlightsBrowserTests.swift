import XCTest

private typealias Sample = StudyReaderUI.Sample

/// T69 checkpoint, sidebar Highlights section (F-13 without Similar and Mastery).
final class HighlightsBrowserTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    private func rows(in ui: StudyReaderUI) -> XCUIElementQuery {
        ui.app.descendants(matching: .any).matching(identifier: "highlight-row")
    }

    /// Whether `element` holds keyboard focus (private XCUIElement attribute, available on macOS).
    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
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

    /// H0: the list and detail fill the window below the filter bar (Spec FAIL at T69: a blank band above the filter
    /// bar and a list squeezed to three rows).
    @MainActor
    func testListAndDetailFillTheWindow() {
        let ui = StudyReaderUI.launch()
        ui.showSection("Highlights")
        let list = ui.app.descendants(matching: .any)["Highlights list"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 8), "No highlights list.")
        let filter = ui.app.descendants(matching: .any)["Filter by document"].firstMatch
        XCTAssertTrue(filter.waitForExistence(timeout: 3), "No filter bar.")
        let window = ui.app.windows.firstMatch.frame
        ui.attachScreenshot("Highlights browser layout", to: self)
        XCTAssertGreaterThanOrEqual(
            list.frame.height, window.height * 0.5,
            "The list is squeezed: \(list.frame.height) pt in a \(window.height) pt window."
        )
        XCTAssertLessThan(
            filter.frame.minY - window.minY, 120,
            "The filter bar sits \(filter.frame.minY - window.minY) pt below the window top (blank band above it)."
        )
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
        let detailNote = ui.app.descendants(matching: .any)["highlight-detail-note"].firstMatch
        XCTAssertTrue(detailNote.waitForExistence(timeout: 5), "The detail pane has no note field.")
    }

    /// Return and Escape typed in the detail pane's note field and Add Tag field stay in those fields: no window opens,
    /// the list and selection are unchanged. (LibraryView and its hidden buttons aren't mounted in this section, so this
    /// guards the browser's own handling; the library's guard is covered by LibraryOpenTests.)
    @MainActor
    func testReturnAndEscapeStayInTheDetailPaneFields() {
        let ui = StudyReaderUI.launch()
        ui.showSection("Highlights")
        let first = rows(in: ui).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        let total = rows(in: ui).count
        first.click()
        let open = ui.app.buttons["Open in Document"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), "No detail pane after selecting a row.")
        let note = ui.app.descendants(matching: .any)["highlight-detail-note"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5), "No note field in the detail pane.")
        ui.attachHierarchy("Browser detail hierarchy", to: self)
        let windows = ui.app.windows.count

        note.click()
        XCTAssertTrue(hasKeyboardFocus(note), "The click didn't focus the note field.")
        ui.app.typeText("zq")
        ui.app.typeKey(.return, modifierFlags: [])
        ui.settle()
        ui.app.typeKey(.escape, modifierFlags: [])
        ui.settle()
        XCTAssertTrue(
            (note.value as? String ?? "").contains("zq"),
            "The typed text isn't in the note field: \(String(describing: note.value))"
        )
        assertBrowserUnchanged(ui, total: total, windows: windows, open: open)

        let tagField = ui.app.textFields["Add tag"].firstMatch
        XCTAssertTrue(tagField.waitForExistence(timeout: 5), "No Add Tag field in the detail pane.")
        tagField.click()
        XCTAssertTrue(hasKeyboardFocus(tagField), "The click didn't focus the Add Tag field.")
        ui.app.typeKey(.return, modifierFlags: [])
        ui.settle()
        ui.app.typeKey(.escape, modifierFlags: [])
        ui.settle()
        assertBrowserUnchanged(ui, total: total, windows: windows, open: open)
    }

    @MainActor
    private func assertBrowserUnchanged(_ ui: StudyReaderUI, total: Int, windows: Int, open: XCUIElement) {
        XCTAssertEqual(ui.app.windows.count, windows, "Return or Escape opened or closed a window.")
        XCTAssertFalse(ui.card(Sample.lecture).exists, "The library appeared after Return or Escape.")
        XCTAssertEqual(rows(in: ui).count, total, "The browser list changed after Return or Escape.")
        XCTAssertTrue(open.exists, "The row was deselected by Return or Escape (the detail pane is gone).")
    }
}
