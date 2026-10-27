import XCTest

private typealias Sample = StudyReaderUI.Sample

/// T63a: highlights in the reader and the Highlights panel (T63 checkpoint coverage C1, C2, C9, C10). Pixel checks
/// assume the light appearance; the seeded highlights come from `SampleLibrary`.
final class ReaderHighlightTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private let seededMarkdownTexts = [
        "lowers the loss",
        "too large a step can diverge",
        "small batch of examples",
        "running average"
    ]

    private let seededLectureTexts = [
        "Proteins embedded in the membrane move materials.",
        "Cristae increase the inner membrane surface area.",
        "The nucleus stores DNA and controls gene expression."
    ]

    @MainActor
    private func open(_ title: String) -> StudyReaderUI {
        let ui = StudyReaderUI.launch()
        ui.openDocument(title)
        return ui
    }

    // MARK: - C1

    /// C1: the seeded highlights of a Markdown document are drawn when it opens, in all four colours.
    @MainActor
    func testSeededMarkdownHighlightsAreDrawn() {
        let ui = open(Sample.gradient)
        let yellow = ui.waitForBand(.yellow, timeout: 5)
        ui.attachScreenshot("C1 Markdown reader", to: self)
        XCTAssertGreaterThanOrEqual(yellow, 100, "The yellow band of \"lowers the loss\" isn't drawn (\(yellow) px).")
        for color in [BandColor.green, .blue, .pink] {
            let count = ui.waitForBand(color, timeout: 3)
            XCTAssertGreaterThanOrEqual(count, 100, "The \(color) band isn't drawn (\(count) px).")
        }
        ui.showHighlightsPanel()
        XCTAssertTrue(ui.waitForRows(4), "The panel doesn't list 4 rows: \(ui.highlightRows.count).")
        ui.attachScreenshot("C1 Markdown panel", to: self)
    }

    // MARK: - C2

    @MainActor
    private func assertRows(_ ui: StudyReaderUI, texts: [String], pages: Bool, badge: Bool) {
        ui.showHighlightsPanel()
        XCTAssertTrue(ui.waitForRows(texts.count), "Expected \(texts.count) rows, found \(ui.highlightRows.count).")
        ui.attachScreenshot("C2 panel rows", to: self)
        ui.attachHierarchy("C2 panel hierarchy", to: self)
        let rows = ui.highlightRows
        for (index, text) in texts.enumerated() where index < rows.count {
            let content = ui.rowText(rows[index])
            XCTAssertTrue(content.contains(text), "Row \(index + 1) should contain \"\(text)\": \(content)")
            XCTAssertEqual(rows[index].label, text, "Row \(index + 1) accessibility label.")
            // Page and badge are the row's accessibility value ("p. 2, PDF"); the row's own content must carry them.
            let detail = rows[index].value as? String ?? ""
            if pages {
                XCTAssertTrue(detail.contains("p. \(index + 1)"), "Row \(index + 1) shows no page number: \(content)")
            } else {
                XCTAssertFalse(
                    content.contains("p. ") || detail.contains("p. "),
                    "Row \(index + 1) shows a page number: \(content) / \(detail)"
                )
            }
            if badge {
                XCTAssertTrue(detail.contains("PDF"), "Row \(index + 1) has no PDF badge: \(content)")
            } else {
                XCTAssertFalse(
                    content.contains("PDF") || detail.contains("PDF"),
                    "Row \(index + 1) has a PDF badge: \(content) / \(detail)"
                )
            }
        }
    }

    /// C2: Lecture slides, 3 rows in page order with page numbers and the PDF badge.
    @MainActor
    func testLecturePanelRowsShowTextInReadingOrder() {
        let ui = open(Sample.lecture)
        assertRows(ui, texts: seededLectureTexts, pages: true, badge: true)
    }

    /// C2: Gradient Descent, 4 rows in reading order, no page number and no badge.
    @MainActor
    func testMarkdownPanelRowsShowTextInReadingOrder() {
        let ui = open(Sample.gradient)
        assertRows(ui, texts: seededMarkdownTexts, pages: false, badge: false)
    }

    /// C2: Probability (a PDF book chapter), 1 row on page 1 with the PDF badge.
    @MainActor
    func testProbabilityPanelShowsItsOneRow() {
        let ui = open(Sample.probability)
        assertRows(
            ui,
            texts: ["Probability assigns a number between zero and one to each event."],
            pages: true,
            badge: true
        )
    }

    // MARK: - C9

    /// Selects everything with ⌘A and presses 3; a blue highlight appears (row +1, blue band), and the selection clears.
    @MainActor
    private func createBlueHighlight(in title: String) {
        let ui = open(title)
        ui.chooseHighlightColor("Question") // not blue, so key 3 is distinguishable (OB1)
        ui.showHighlightsPanel()
        let rowsBefore = ui.highlightRows.count
        XCTAssertGreaterThan(rowsBefore, 0, "No seeded rows in the panel.")
        ui.settle(1)
        let blueBefore = ui.bandPixels(.blue)

        ui.clickBlankReaderArea()
        ui.app.typeKey("a", modifierFlags: .command)
        ui.settle(0.5)
        ui.app.typeKey("3", modifierFlags: [])
        XCTAssertTrue(ui.waitForRows(rowsBefore + 1), "3 didn't add a row: \(ui.highlightRows.count) vs \(rowsBefore).")
        ui.settle(1)
        let blueAfter = ui.bandPixels(.blue)
        ui.attachScreenshot("C9 \(title) after 3", to: self)
        XCTAssertGreaterThan(blueAfter, blueBefore + 200, "No new blue band (\(blueBefore) -> \(blueAfter) px).")

        // The selection cleared: another 3 has nothing to highlight.
        ui.app.typeKey("3", modifierFlags: [])
        ui.settle(1)
        XCTAssertEqual(ui.highlightRows.count, rowsBefore + 1, "The selection didn't clear: 3 added another row.")
    }

    @MainActor
    func testKeyThreeHighlightsTheSelectionInAPDF() {
        createBlueHighlight(in: Sample.lecture)
    }

    @MainActor
    func testKeyThreeHighlightsTheSelectionInMarkdown() {
        createBlueHighlight(in: Sample.gradient)
    }

    /// C9: 3 with no selection, and ⌘3 / ⌥3 with a selection, change nothing.
    @MainActor
    private func assertKeyThreeIsInertWithoutSelectionOrWithModifiers(in title: String) {
        let ui = open(title)
        ui.chooseHighlightColor("Question")
        ui.showHighlightsPanel()
        let rows = ui.highlightRows.count
        ui.clickBlankReaderArea()
        ui.app.typeKey("3", modifierFlags: [])
        ui.settle(1)
        XCTAssertEqual(ui.highlightRows.count, rows, "3 without a selection changed the panel.")

        ui.app.typeKey("a", modifierFlags: .command)
        ui.settle(0.5)
        ui.app.typeKey("3", modifierFlags: .command)
        ui.settle(1)
        XCTAssertEqual(ui.highlightRows.count, rows, "⌘3 changed the panel.")
        ui.app.typeKey("3", modifierFlags: .option)
        ui.settle(1)
        XCTAssertEqual(ui.highlightRows.count, rows, "⌥3 changed the panel.")
    }

    @MainActor
    func testKeyThreeIsInertWithoutSelectionOrWithModifiersInAPDF() {
        assertKeyThreeIsInertWithoutSelectionOrWithModifiers(in: Sample.lecture)
    }

    @MainActor
    func testKeyThreeIsInertWithoutSelectionOrWithModifiersInMarkdown() {
        assertKeyThreeIsInertWithoutSelectionOrWithModifiers(in: Sample.gradient)
    }

    // MARK: - C10

    /// After the highlight is made, Edit > Undo Highlight is enabled and ⌘Z removes the row and its band.
    @MainActor
    private func assertUndoRemovesTheHighlight(in title: String) {
        let ui = open(title)
        ui.chooseHighlightColor("Question")
        ui.showHighlightsPanel()
        let rowsBefore = ui.highlightRows.count
        ui.settle(1)
        let blueBefore = ui.bandPixels(.blue)
        ui.clickBlankReaderArea()
        ui.app.typeKey("a", modifierFlags: .command)
        ui.settle(0.5)
        ui.app.typeKey("3", modifierFlags: [])
        XCTAssertTrue(ui.waitForRows(rowsBefore + 1), "3 didn't add a row.")
        ui.settle(1)

        let undo = ui.menuItemState("Edit", "Undo Highlight")
        XCTAssertTrue(
            undo.exists,
            "Edit has no \"Undo Highlight\" item; its items: \(ui.menuTitles("Edit")); " +
                "Undo enabled: \(ui.menuItemState("Edit", "Undo").enabled)."
        )
        XCTAssertTrue(undo.enabled, "Edit > Undo Highlight is disabled.")

        ui.app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(ui.waitForRows(rowsBefore), "⌘Z didn't remove the row: \(ui.highlightRows.count).")
        ui.settle(1)
        let blueAfter = ui.bandPixels(.blue)
        ui.attachScreenshot("C10 \(title) after undo", to: self)
        XCTAssertLessThanOrEqual(blueAfter, blueBefore + 50, "The blue band stays after ⌘Z (\(blueBefore) -> \(blueAfter) px).")
    }

    @MainActor
    func testUndoRemovesTheHighlightInAPDF() {
        assertUndoRemovesTheHighlight(in: Sample.lecture)
    }

    @MainActor
    func testUndoRemovesTheHighlightInMarkdown() {
        assertUndoRemovesTheHighlight(in: Sample.gradient)
    }
}

extension StudyReaderUI {
    /// True when any static text in the window has `text` as its label or value (the combined panel row may hide it).
    func panelHasText(_ text: String) -> Bool {
        app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", text, text)).count > 0
    }
}
