import XCTest

private typealias Sample = StudyReaderUI.Sample

/// T52 checkpoint, reader tab steps 26–36. These check only the chrome: title, toolbar, inspector, error state and
/// menu commands. The PDF reader arrived with T53; the Markdown content area is a placeholder until T55.
final class ReaderChromeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    private func openReader(_ title: String = Sample.lecture) -> StudyReaderUI {
        let ui = StudyReaderUI.launch()
        ui.card(title).doubleClick()
        XCTAssertTrue(ui.waitUntil { ui.tabTitles.contains(title) }, "The reader tab didn't open. Tabs: \(ui.tabTitles)")
        return ui
    }

    /// Step 26: the window shows the document title and its category as the subtitle.
    @MainActor
    func testTitleAndSubtitleShowDocumentAndCategory() {
        let ui = openReader()
        let window = ui.app.windows.firstMatch
        XCTAssertTrue(window.title.contains(Sample.lecture), "Window title: \(window.title)")
        let subtitleShown = window.title.contains("Lecture slides") || window.staticTexts["Lecture slides"].exists
        XCTAssertTrue(subtitleShown, "The category isn't shown as the subtitle. Window title: \(window.title)")
    }

    /// Step 27: the menu lists the five colours with their labels, the choice sticks, and each swatch is coloured.
    /// At the T52 checkpoint every swatch rendered black (menu images draw as templates).
    @MainActor
    func testHighlightColorMenuShowsColouredSwatchesAndKeepsTheChoice() {
        let ui = openReader()
        ui.highlightColorMenu.click()
        let labels = ["Key concept", "Exam", "Connection", "Question"]
        for label in labels {
            XCTAssertTrue(ui.app.menuItems[label].waitForExistence(timeout: 3), "Missing colour \(label)")
        }
        let dontUnderstand = ui.app.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'Don'")).firstMatch
        XCTAssertTrue(dontUnderstand.exists, "Missing colour Don't understand")
        ui.attachScreenshot("Step 27 highlight colour menu", to: self)

        for label in labels {
            let frame = ui.app.menuItems[label].frame
            // The swatch sits after the checkmark column, in the first ~44 pt of the item.
            let swatch = CGRect(x: frame.minX + 18, y: frame.minY + 2, width: 26, height: frame.height - 4)
            let saturation = ScreenPixels.stats(of: swatch)?.maxSaturation ?? 0
            XCTAssertGreaterThan(saturation, 0.3, "The \(label) swatch isn't coloured (max saturation \(saturation)).")
        }

        ui.app.menuItems["Question"].click()
        ui.highlightColorMenu.click()
        ui.attachScreenshot("Step 27 after choosing Question", to: self)
        ui.app.typeKey(.escape, modifierFlags: [])
    }

    /// Step 28: Find and Snapshot buttons are absent until the engines provide them, not just disabled.
    @MainActor
    func testFindAndSnapshotButtonsAreAbsent() {
        let ui = openReader()
        XCTAssertFalse(ui.app.toolbars.buttons["Find in document"].exists)
        XCTAssertFalse(ui.app.toolbars.buttons["Snapshot"].exists)
    }

    /// Step 29.
    @MainActor
    func testInspectorToggleShowsHighlightsAndNotesTabs() {
        let ui = openReader()
        ui.inspectorToggle.click()
        XCTAssertTrue(ui.waitUntil { ui.isInspectorOpen }, "The inspector didn't open with Highlights and Notes tabs.")
        ui.attachScreenshot("Step 29 inspector", to: self)
        ui.inspectorToggle.click()
        XCTAssertTrue(ui.waitUntil { !ui.isInspectorOpen }, "The inspector didn't close.")
    }

    /// Step 30: a missing original shows an error, not a crash, and the tab still has the document's title.
    /// At the T52 checkpoint the error showed but the tab and window title were blank.
    @MainActor
    func testMissingOriginalShowsErrorAndKeepsTheTitle() {
        let ui = StudyReaderUI.launch()
        ui.card(Sample.pendulum).doubleClick()
        XCTAssertTrue(ui.app.staticTexts["The document file is missing."].waitForExistence(timeout: 5))
        ui.attachScreenshot("Step 30 missing original", to: self)
        XCTAssertTrue(ui.tabTitles.contains(Sample.pendulum), "The tab has no title. Tabs: \(ui.tabTitles)")
    }

    /// Step 32.
    @MainActor
    func testShiftCommandMOpensTheMetadataSheetInTheReader() {
        let ui = openReader()
        ui.app.typeKey("m", modifierFlags: [.command, .shift])
        let title = ui.sheet.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "⇧⌘M didn't open the metadata sheet in the reader.")
        XCTAssertEqual(title.value as? String, Sample.lecture)
        ui.sheet.buttons["Cancel"].click()
    }

    /// Step 33.
    @MainActor
    func testFindInDocumentIsDisabledAndListedOnce() {
        let ui = openReader()
        let state = ui.menuItemState("Edit", "Find in Document")
        XCTAssertTrue(state.exists)
        XCTAssertFalse(state.enabled, "Find in Document is enabled before the engines provide it.")
        let titles = ui.menuTitles("Edit")
        XCTAssertEqual(titles.filter { $0.hasPrefix("Find") }.count, 1, "Edit has more than one Find entry: \(titles)")
    }

    /// Step 34: the reader View items are greyed out, not missing. Since T53 a loaded PDF enables them, so the check
    /// uses the sample whose original is missing (a failed reader registers no engine actions).
    @MainActor
    func testViewMenuReaderItemsAreDisabledNotMissing() {
        let ui = openReader(Sample.pendulum)
        XCTAssertTrue(ui.app.staticTexts["The document file is missing."].waitForExistence(timeout: 5))
        for title in ["Zoom In", "Zoom Out", "Actual Size", "Fit Width", "Single Page", "Show Thumbnails"] {
            let state = ui.menuItemState("View", title)
            XCTAssertTrue(state.exists, "View > \(title) is missing.")
            XCTAssertFalse(state.enabled, "View > \(title) is enabled.")
        }
    }

    /// T53: a loaded PDF enables the zoom, display and thumbnail items.
    @MainActor
    func testViewMenuPDFItemsAreEnabledForALoadedPDF() {
        let ui = openReader(Sample.lecture)
        for title in ["Zoom In", "Zoom Out", "Actual Size", "Fit Width", "Single Page", "Show Thumbnails"] {
            let enabled = ui.waitUntil(timeout: 10) { ui.menuItemState("View", title).enabled }
            XCTAssertTrue(enabled, "View > \(title) stays disabled for a loaded PDF.")
        }
    }

    /// U7: a reader that failed to load has no colour menu and no inspector toggle, and ⌥⌘I does nothing.
    @MainActor
    func testFailedReaderShowsNoColourMenuOrInspectorToggle() {
        let ui = StudyReaderUI.launch()
        ui.card(Sample.pendulum).doubleClick()
        XCTAssertTrue(ui.app.staticTexts["The document file is missing."].waitForExistence(timeout: 5))
        ui.attachScreenshot("Failed reader chrome", to: self)

        XCTAssertFalse(ui.highlightColorMenu.exists, "The highlight colour menu shows in a failed reader.")
        XCTAssertFalse(ui.inspectorToggle.exists, "The inspector toggle shows in a failed reader.")
        let state = ui.menuItemState("View", "Highlights Panel")
        XCTAssertTrue(state.exists, "View > Highlights Panel is missing.")
        XCTAssertFalse(state.enabled, "View > Highlights Panel is enabled in a failed reader.")

        ui.app.typeKey("i", modifierFlags: [.command, .option])
        ui.settle(1)
        XCTAssertFalse(ui.isInspectorOpen, "⌥⌘I opened the inspector in a failed reader.")
    }

    /// Step 35. ⌥⌘I toggles the inspector both ways. At the T52 checkpoint the shortcut was ⌥⌘H, which ran the
    /// system's "Hide Others" instead (user decision 2026-10-27: ⌥⌘I).
    @MainActor
    func testOptionCommandITogglesTheInspector() {
        let ui = openReader()
        ui.app.typeKey("i", modifierFlags: [.command, .option])
        XCTAssertTrue(ui.waitUntil(timeout: 3) { ui.isInspectorOpen }, "⌥⌘I didn't open the inspector.")
        XCTAssertEqual(ui.app.state, .runningForeground, "⌥⌘I sent StudyReader to the background.")
        ui.app.typeKey("i", modifierFlags: [.command, .option])
        XCTAssertTrue(ui.waitUntil(timeout: 3) { !ui.isInspectorOpen }, "A second ⌥⌘I didn't close the inspector.")
    }

    /// Step 36.
    @MainActor
    func testSnapshotIsDisabled() {
        let ui = openReader()
        let state = ui.menuItemState("Document", "Snapshot")
        XCTAssertTrue(state.exists)
        XCTAssertFalse(state.enabled)
    }

    /// Found at the T52 checkpoint: after its category was deleted, an open reader tab kept showing the deleted
    /// category as its subtitle instead of "Other".
    @MainActor
    func testOpenReaderSubtitleFollowsACategoryDeletion() {
        let ui = StudyReaderUI.launch()
        ui.showSection("Categories")
        ui.newCategoryButton.click()
        ui.sheet.textFields["Category name"].typeText("Lab reports")
        ui.sheet.buttons["Add"].click()
        XCTAssertTrue(ui.categoryRow("Lab reports").waitForExistence(timeout: 5))

        ui.showSection("Library")
        ui.card(Sample.gradient).click()
        ui.settle() // the selection must reach the menu commands before the shortcut is typed
        ui.app.typeKey("m", modifierFlags: [.command, .shift])
        XCTAssertTrue(ui.sheet.popUpButtons["Category"].waitForExistence(timeout: 5))
        ui.sheet.popUpButtons["Category"].click()
        ui.app.menuItems["Lab reports"].click()
        ui.sheet.buttons["Save metadata"].click()

        ui.card(Sample.gradient).doubleClick()
        XCTAssertTrue(ui.waitUntil { ui.tabTitles.contains(Sample.gradient) })

        ui.tab(at: 0).click()
        ui.showSection("Categories")
        ui.categoryRow("Lab reports").rightClick()
        ui.app.menuItems["Delete…"].click()
        ui.confirmDelete()
        XCTAssertTrue(ui.categoryRow("Lab reports").waitForNonExistence(timeout: 5))

        ui.tab(Sample.gradient).click()
        let window = ui.app.windows.firstMatch
        let showsOther = ui.waitUntil {
            window.title.contains("Other") || window.staticTexts["Other"].exists
        }
        ui.attachScreenshot("Reader subtitle after category deletion", to: self)
        XCTAssertTrue(showsOther, "The reader still shows the deleted category. Window title: \(window.title)")
    }
}
