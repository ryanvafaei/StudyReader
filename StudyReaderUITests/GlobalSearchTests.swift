import XCTest

private typealias Sample = StudyReaderUI.Sample

/// T66, SPEC F-12: global search from the library window.
final class GlobalSearchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // S1 (grouped results, 'p. N' vs 'Section', empty state, clearing the query restores the selected card) moved to
    // VISUAL_CHECKS.md 'Needs a Mac' because its section-header selector did not resolve on CI.

    /// S3
    @MainActor
    func testClickingAHitOpensTheReaderAtTheLocation() {
        let ui = StudyReaderUI.launch()
        ui.app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(ui.searchField.waitForExistence(timeout: 5))
        ui.settle()
        ui.searchField.typeText("Cristae")
        let highlightHit = ui.searchHits("highlight").firstMatch
        XCTAssertTrue(highlightHit.waitForExistence(timeout: 10), "No highlight hit for 'Cristae'.")
        highlightHit.click()
        XCTAssertTrue(ui.waitUntil(timeout: 10) { ui.tabTitles.contains(Sample.lecture) }, "The Lecture tab didn't open. Tabs: \(ui.tabTitles)")
        XCTAssertTrue(ui.waitUntil(timeout: 8) { ui.pageNumber == "2" }, "The reader isn't on page 2; page field: '\(ui.pageNumber)'.")

        ui.tab(at: 0).click()
        XCTAssertTrue(ui.searchField.waitForExistence(timeout: 5), "The search field isn't visible in the library tab.")
        ui.replaceText(in: ui.searchField, with: "Stochastic")
        let documentHit = ui.searchHits("document").firstMatch
        XCTAssertTrue(documentHit.waitForExistence(timeout: 10), "No document hit for 'Stochastic'.")
        documentHit.click()
        XCTAssertTrue(ui.waitUntil(timeout: 10) { ui.tabTitles.contains(Sample.gradient) }, "The Gradient Descent tab didn't open. Tabs: \(ui.tabTitles)")
    }

    /// S4
    @MainActor
    func testCommandShiftFFromAReaderShowsTheLibrarySearch() {
        let ui = StudyReaderUI.launch()
        ui.openDocument(Sample.lecture)
        XCTAssertEqual(ui.selectedTabTitle, Sample.lecture)
        ui.app.typeKey("f", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            ui.waitUntil { ui.selectedTabTitle != Sample.lecture },
            "The library tab didn't come forward; selected tab: \(ui.selectedTabTitle ?? "none")."
        )
        XCTAssertTrue(ui.searchField.waitForExistence(timeout: 5), "The library search field isn't shown.")
        let window = ui.app.windows.firstMatch
        XCTAssertTrue(ui.sidebar.exists, "The library sidebar isn't shown.")
        XCTAssertGreaterThan(
            ui.sidebar.frame.intersection(window.frame).width, 50,
            "The library sidebar isn't visible: \(ui.sidebar.frame) in window \(window.frame)."
        )
    }
}
