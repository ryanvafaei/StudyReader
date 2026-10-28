import XCTest

private typealias Sample = StudyReaderUI.Sample

/// T52 checkpoint, sidebar Tags steps 17–20 (T49).
final class TagManagerTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// A tag row is one combined static text: "<name>, N highlights, M documents".
    @MainActor
    private func tagRow(_ name: String, in ui: StudyReaderUI) -> XCUIElement {
        let prefix = name + ","
        return ui.app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", prefix, prefix)).firstMatch
    }

    /// Step 17, empty state.
    @MainActor
    func testEmptyStateWithoutTags() {
        let ui = StudyReaderUI.launch(seed: false)
        ui.showSection("Tags")
        XCTAssertTrue(ui.app.staticTexts["No tags yet"].waitForExistence(timeout: 5))
        ui.attachScreenshot("Step 17 empty state", to: self)
    }

    /// Step 17, counts like "2 highlights, 1 document" after seeding.
    @MainActor
    func testRowsShowHighlightAndDocumentCounts() {
        let ui = StudyReaderUI.launch()
        ui.showSection("Tags")
        XCTAssertTrue(tagRow("Sample · exam", in: ui).waitForExistence(timeout: 5))
        let counts = ui.app.staticTexts.matching(NSPredicate(
            format: "(label CONTAINS 'highlight' AND label CONTAINS 'document') OR (value CONTAINS 'highlight' AND value CONTAINS 'document')"
        ))
        XCTAssertGreaterThanOrEqual(counts.count, 4, "Expected a count line per tag.")
        ui.attachScreenshot("Step 17 counts", to: self)
    }

    /// Step 18.
    @MainActor
    func testRenameToAnExistingNameShowsAnInlineError() {
        let ui = StudyReaderUI.launch()
        ui.showSection("Tags")
        tagRow("Sample · midterm", in: ui).rightClick()
        ui.app.menuItems["Rename…"].click()
        let field = ui.sheet.textFields["Tag name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        ui.replaceText(in: field, with: "Sample · exam")
        ui.sheet.buttons["Rename"].click()
        XCTAssertTrue(ui.sheet.staticTexts["A tag with this name already exists."].waitForExistence(timeout: 3))
        XCTAssertTrue(ui.sheet.exists, "The rename sheet closed on a duplicate name.")

        ui.replaceText(in: field, with: "Sample · midterm renamed")
        ui.sheet.buttons["Rename"].click()
        XCTAssertTrue(tagRow("Sample · midterm renamed", in: ui).waitForExistence(timeout: 8))
    }

    /// Step 19.
    @MainActor
    func testMergeAsksForConfirmationAndRemovesTheSource() {
        let ui = StudyReaderUI.launch()
        ui.showSection("Tags")
        tagRow("Sample · mid-term", in: ui).rightClick()
        ui.app.menuItems["Merge into…"].hover()
        ui.app.menuItems["Sample · midterm"].click()
        let merge = ui.alertButton("Merge")
        XCTAssertTrue(merge.waitForExistence(timeout: 3), "No confirmation before merging.")
        merge.click()
        XCTAssertTrue(tagRow("Sample · mid-term", in: ui).waitForNonExistence(timeout: 5))
        XCTAssertTrue(tagRow("Sample · midterm", in: ui).exists)
    }

    /// Step 20: deleting a tag keeps its documents and highlights.
    @MainActor
    func testDeleteKeepsTheDocuments() {
        let ui = StudyReaderUI.launch()
        ui.showSection("Tags")
        tagRow("Sample · reviewed", in: ui).rightClick()
        ui.app.menuItems["Delete…"].click()
        ui.confirmDelete()
        XCTAssertTrue(tagRow("Sample · reviewed", in: ui).waitForNonExistence(timeout: 5))
        ui.showSection("Library")
        for title in [Sample.lecture, Sample.sparse, Sample.gradient, Sample.retrieval, Sample.membrane] {
            XCTAssertTrue(ui.card(title).waitForExistence(timeout: 3), "\(title) disappeared after deleting a tag.")
        }
    }
}
