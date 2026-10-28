import XCTest

private typealias Sample = StudyReaderUI.Sample

/// T63, SPEC F-06: the reader's Highlights panel.
final class HighlightsPanelTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// C3
    @MainActor
    func testEmptyStateWhenTheDocumentHasNoHighlights() {
        let ui = StudyReaderUI.launch()
        ui.openDocument(Sample.sparse)
        ui.showHighlightsPanel()
        XCTAssertTrue(
            ui.staticText("No highlights yet. Select text to highlight it.").waitForExistence(timeout: 10),
            "The empty-state text isn't shown."
        )
        XCTAssertEqual(ui.highlightRows.count, 0)
    }

    /// C6: clicking a row jumps to its page.
    @MainActor
    func testClickingARowJumpsToItsPage() {
        let ui = StudyReaderUI.launch()
        ui.openDocument(Sample.lecture)
        ui.showHighlightsPanel()
        XCTAssertTrue(ui.waitForRows(3), "The panel lists \(ui.highlightRows.count) rows, expected 3.")
        ui.attachHierarchy("Highlights panel hierarchy", to: self)

        for page in ["1", "3"] {
            guard let row = ui.highlightRows.first(where: { ui.rowText($0).contains("p. \(page)") }) else {
                XCTFail("No row for page \(page): \(ui.highlightRows.map { ui.rowText($0) })")
                continue
            }
            row.click()
            XCTAssertTrue(ui.waitUntil(timeout: 8) { ui.pageNumber == page }, "Clicking the p. \(page) row left the page at '\(ui.pageNumber)'.")
        }
    }
}
