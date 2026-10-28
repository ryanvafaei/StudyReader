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
        XCTAssertTrue(ui.hasKeyboardFocus(note), "The click didn't focus the note field.")
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
        XCTAssertTrue(ui.hasKeyboardFocus(tagField), "The click didn't focus the Add Tag field.")
        XCTAssertTrue(
            ui.waitUntil { ui.app.staticTexts["No tags yet"].exists || !self.assignedTagLabels(in: ui).isEmpty },
            "The detail pane's tags never loaded."
        )
        let tagsBefore = assignedTagLabels(in: ui)
        ui.app.typeKey(.return, modifierFlags: [])
        ui.settle()
        XCTAssertEqual(
            tagField.value as? String ?? "", "",
            "Return in the empty Add Tag field changed its value: \(String(describing: tagField.value))"
        )
        XCTAssertEqual(
            assignedTagLabels(in: ui), tagsBefore,
            "Return in the empty Add Tag field created a tag (the detail pane's tag chips changed)."
        )
        ui.app.typeKey(.escape, modifierFlags: [])
        ui.settle()
        assertBrowserUnchanged(ui, total: total, windows: windows, open: open)
    }

    /// The labels of the tag chips' remove buttons ("Remove tag <name>", TagFieldView) in the detail pane, sorted. A new
    /// tag adds a chip, so this changes when one is created. The bulk-edit "Remove tag from selection" button isn't a chip.
    @MainActor
    private func assignedTagLabels(in ui: StudyReaderUI) -> [String] {
        ui.app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH 'Remove tag ' AND label != 'Remove tag from selection'"))
            .allElementsBoundByIndex
            .map(\.label)
            .sorted()
    }

    // MARK: - T89: filters, multi-select, bulk actions, open in document, unconfigured export

    private static let total = "10 highlights"

    /// Launches with the seed, opens the section and waits for all ten rows' count text.
    @MainActor
    private func launchBrowser() -> StudyReaderUI {
        let ui = StudyReaderUI.launch()
        ui.showSection("Highlights")
        XCTAssertTrue(countText(ui, Self.total).waitForExistence(timeout: 8), "The browser never showed \"\(Self.total)\".")
        return ui
    }

    /// The count text in the filter bar: a static text whose label or value equals `text`.
    @MainActor
    private func countText(_ ui: StudyReaderUI, _ text: String) -> XCUIElement {
        ui.staticText(text)
    }

    @MainActor
    private func expectCount(_ ui: StudyReaderUI, _ text: String, _ message: String) {
        XCTAssertTrue(countText(ui, text).waitForExistence(timeout: 8), "\(message) Expected \"\(text)\".")
    }

    /// Opens the filter popup `name` ("document", "category", "note", "view", "tag") and clicks the menu item `title`.
    @MainActor
    private func choose(_ ui: StudyReaderUI, _ name: String, _ title: String) {
        let control = ui.app.descendants(matching: .any)["Filter by \(name)"].firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 3), "No \"Filter by \(name)\" control.")
        control.click()
        let item = ui.app.menuItems[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3), "The \"Filter by \(name)\" menu has no item \"\(title)\".")
        item.click()
        ui.settle(0.5)
    }

    @MainActor
    private func clearFilters(_ ui: StudyReaderUI) {
        ui.app.buttons["Clear filters"].firstMatch.click()
        expectCount(ui, Self.total, "Clear didn't restore the list.")
    }

    /// The bulk bar's "Selected" text (label "Selected", value = how many rows are selected).
    @MainActor
    private func selectedElement(_ ui: StudyReaderUI) -> XCUIElement {
        ui.app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Selected'")).firstMatch
    }

    @MainActor
    private func selectedValue(_ ui: StudyReaderUI) -> String {
        let element = selectedElement(ui)
        return element.exists ? "\(element.value ?? "")" : "(no Selected element)"
    }

    @MainActor
    private func expectSelected(_ ui: StudyReaderUI, _ count: Int) {
        XCTAssertTrue(
            ui.waitUntil(timeout: 5) { self.selectedValue(ui) == "\(count)" },
            "Expected Selected = \(count), got \(selectedValue(ui))."
        )
    }

    /// Plain-clicks the first row and ⌘-clicks the next `count - 1` (the bulk bar appears with the second row, so rows
    /// are looked up again before each click).
    @MainActor
    private func selectRows(_ ui: StudyReaderUI, count: Int) {
        XCTAssertTrue(ui.waitUntil(timeout: 8) { ui.highlightRows.count >= count }, "Fewer than \(count) rows to select.")
        ui.highlightRows[0].click()
        ui.settle(0.5)
        for index in 1..<count {
            let row = ui.highlightRows[index]
            XCUIElement.perform(withKeyModifiers: .command) { row.click() }
            ui.settle(0.5)
        }
    }

    /// The row whose value ("<document>, p. N, <Colour>") contains `text`.
    @MainActor
    private func row(_ ui: StudyReaderUI, containing text: String) -> XCUIElement {
        rows(in: ui).matching(NSPredicate(format: "value CONTAINS %@", text)).firstMatch
    }

    /// H1: the count text is singular for one highlight and plural otherwise.
    @MainActor
    func testCountTextSingularAndPlural() {
        let ui = launchBrowser()
        ui.attachHierarchy("Browser hierarchy", to: self)
        let purple = ui.app.buttons["Filter by Purple"]
        XCTAssertTrue(purple.waitForExistence(timeout: 3), "No Purple color filter.")
        purple.click()
        expectCount(ui, "1 highlight", "The Purple filter didn't show the singular count.")
        XCTAssertTrue(ui.waitUntil { self.rows(in: ui).count == 1 }, "Purple should leave exactly 1 row, got \(rows(in: ui).count).")
        clearFilters(ui)
    }

    /// H2: each filter kind narrows the count, and Clear restores it.
    @MainActor
    func testDocumentCategoryNoteViewAndColourFiltersNarrow() {
        let ui = launchBrowser()

        choose(ui, "document", Sample.lecture)
        expectCount(ui, "3 highlights", "The Lecture document filter didn't narrow the list.")
        clearFilters(ui)

        choose(ui, "category", "Notes")
        expectCount(ui, "4 highlights", "The Notes category filter didn't narrow the list.")
        ui.attachScreenshot("Category filter Notes", to: self)
        clearFilters(ui)

        choose(ui, "note", "With note")
        expectCount(ui, "2 highlights", "\"With note\" didn't narrow the list.")
        choose(ui, "note", "Without note")
        expectCount(ui, "8 highlights", "\"Without note\" didn't narrow the list.")
        clearFilters(ui)

        choose(ui, "view", "Markdown")
        expectCount(ui, "4 highlights", "The Markdown view filter didn't narrow the list.")
        clearFilters(ui)

        ui.app.buttons["Filter by Yellow"].click()
        ui.app.buttons["Filter by Pink"].click()
        expectCount(ui, "5 highlights", "Yellow and Pink together didn't show 3 + 2 highlights.")
        clearFilters(ui)
    }

    /// H4: ⌘-click and ⇧-click select several rows, and the bulk bar offers its five actions.
    @MainActor
    func testCommandAndShiftClickSelectSeveralRowsAndShowTheBulkBar() {
        let ui = launchBrowser()
        XCTAssertFalse(selectedElement(ui).exists, "The bulk bar showed before anything was selected.")

        selectRows(ui, count: 2)
        expectSelected(ui, 2)
        XCTAssertTrue(ui.staticText("2 highlights selected").waitForExistence(timeout: 5), "The detail pane doesn't say \"2 highlights selected\".")
        for label in [
            "Add tag to selection", "Remove tag from selection", "Change color of selection", "Export selection", "Delete selection",
        ] {
            XCTAssertTrue(
                ui.app.descendants(matching: .any)[label].firstMatch.exists,
                "The bulk bar has no \"\(label)\" control."
            )
        }
        ui.attachScreenshot("Bulk bar", to: self)
        ui.attachHierarchy("Bulk bar hierarchy", to: self)

        ui.highlightRows[0].click()
        ui.settle(0.5)
        let third = ui.highlightRows[2]
        XCUIElement.perform(withKeyModifiers: .shift) { third.click() }
        ui.settle(0.5)
        expectSelected(ui, 3)
    }

    /// H5: bulk add and remove a tag. Return and Escape in the "Tag name" field stay in the popover (standing rule).
    @MainActor
    func testBulkAddAndRemoveTag() {
        let ui = launchBrowser()
        let windows = ui.app.windows.count
        selectRows(ui, count: 2)
        expectSelected(ui, 2)
        let rowsBefore = rows(in: ui).count

        let add = ui.app.buttons["Add tag to selection"]
        add.click()
        let field = ui.app.textFields["Tag name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The Add Tag popover has no \"Tag name\" field.")
        XCTAssertTrue(ui.hasKeyboardFocus(field), "The \"Tag name\" field doesn't have keyboard focus.")
        ui.app.typeText("uitag")
        ui.app.typeKey(.return, modifierFlags: [])
        ui.settle(1)
        XCTAssertEqual(ui.app.windows.count, windows, "Return in the Tag name field opened or closed a window.")
        XCTAssertFalse(ui.card(Sample.lecture).exists, "Return in the Tag name field showed the library.")
        XCTAssertEqual(rows(in: ui).count, rowsBefore, "The list changed after Return in the Tag name field.")

        choose(ui, "tag", "uitag")
        expectCount(ui, "2 highlights", "Filtering by the new tag should leave the two tagged rows.")
        selectRows(ui, count: 2)
        expectSelected(ui, 2)
        let remove = ui.app.descendants(matching: .any)["Remove tag from selection"].firstMatch
        remove.click()
        let tagItem = ui.app.menuItems["uitag"].firstMatch
        XCTAssertTrue(tagItem.waitForExistence(timeout: 3), "\"Remove tag from selection\" doesn't list uitag.")
        tagItem.click()
        XCTAssertTrue(
            ui.staticText("No highlights match these filters").waitForExistence(timeout: 8),
            "Removing the tag from both rows should empty the tag-filtered list."
        )
        clearFilters(ui)

        selectRows(ui, count: 2)
        expectSelected(ui, 2)
        add.click()
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The Add Tag popover didn't reopen.")
        ui.app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(ui.waitUntil { !field.exists }, "Escape didn't close the Add Tag popover.")
        expectSelected(ui, 2)
        XCTAssertEqual(ui.app.windows.count, windows, "Escape in the Tag name field opened or closed a window.")
        XCTAssertFalse(
            ui.app.descendants(matching: .any)["Remove tag from selection"].firstMatch.isEnabled,
            "Escape added a tag: \"Remove tag from selection\" is enabled."
        )
    }

    /// H6: bulk colour change moves rows between filters; bulk delete asks first, with a singular and plural title.
    @MainActor
    func testBulkColourAndDeleteWithConfirmation() {
        let ui = launchBrowser()

        ui.app.buttons["Filter by Yellow"].click()
        expectCount(ui, "3 highlights", "The Yellow filter didn't narrow the list.")
        selectRows(ui, count: 2)
        expectSelected(ui, 2)
        ui.app.descendants(matching: .any)["Change color of selection"].firstMatch.click()
        let blue = ui.app.menuItems["Blue"].firstMatch
        XCTAssertTrue(blue.waitForExistence(timeout: 3), "The colour menu has no Blue item.")
        blue.click()
        expectCount(ui, "1 highlight", "Two yellow rows turned blue but are still shown under the Yellow filter.")
        clearFilters(ui)

        ui.app.buttons["Filter by Blue"].click()
        expectCount(ui, "4 highlights", "Blue should now hold the 2 seeded and the 2 recoloured highlights.")
        selectRows(ui, count: 2)
        expectSelected(ui, 2)
        ui.app.buttons["Delete selection"].click()
        XCTAssertTrue(ui.staticText("Delete 2 highlights?").waitForExistence(timeout: 5), "No \"Delete 2 highlights?\" confirmation.")
        ui.attachScreenshot("Delete confirmation", to: self)
        ui.alertButton("Cancel").click()
        expectCount(ui, "4 highlights", "Cancel deleted highlights.")

        ui.app.buttons["Delete selection"].click()
        XCTAssertTrue(ui.staticText("Delete 2 highlights?").waitForExistence(timeout: 5), "The confirmation didn't reappear.")
        ui.confirmDelete()
        expectCount(ui, "2 highlights", "Confirming the delete didn't remove the two rows.")

        ui.highlightRows[0].rightClick()
        let delete = ui.app.menuItems["Delete…"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "The row's context menu has no \"Delete…\".")
        delete.click()
        XCTAssertTrue(ui.staticText("Delete 1 highlight?").waitForExistence(timeout: 5), "No singular \"Delete 1 highlight?\" confirmation.")
        ui.alertButton("Cancel").click()
        expectCount(ui, "2 highlights", "Cancelling the singular delete removed a row.")
    }

    /// H9: Open in Document works from the detail button, the context menu and a double click; a second open of the same
    /// document selects its tab instead of adding one.
    @MainActor
    func testOpenInDocumentFromButtonContextMenuAndDoubleClick() {
        let ui = launchBrowser()

        choose(ui, "document", Sample.lecture)
        expectCount(ui, "3 highlights", "The Lecture document filter didn't narrow the list.")
        let page3 = row(ui, containing: "p. 3")
        XCTAssertTrue(page3.waitForExistence(timeout: 5), "No Lecture row on page 3.")
        page3.click()
        let open = ui.app.buttons["Open in Document"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), "No detail pane after selecting the row.")
        open.click()
        XCTAssertTrue(ui.waitUntil(timeout: 8) { ui.tabTitles.contains(Sample.lecture) }, "The Lecture tab didn't open. Tabs: \(ui.tabTitles)")
        XCTAssertTrue(
            ui.waitUntil(timeout: 8) { ui.pageNumber == "3" },
            "The reader didn't land on page 3, the page field shows \"\(ui.pageNumber)\"."
        )

        ui.tab(at: 0).click()
        ui.settle(1)
        clearFilters(ui)
        choose(ui, "document", Sample.gradient)
        expectCount(ui, "4 highlights", "The Gradient Descent document filter didn't narrow the list.")
        ui.highlightRows[0].rightClick()
        let contextOpen = ui.app.menuItems["Open in Document"].firstMatch
        XCTAssertTrue(contextOpen.waitForExistence(timeout: 3), "The row's context menu has no \"Open in Document\".")
        contextOpen.click()
        XCTAssertTrue(ui.waitUntil(timeout: 8) { ui.tabTitles.contains(Sample.gradient) }, "The Gradient tab didn't open. Tabs: \(ui.tabTitles)")

        ui.tab(at: 0).click()
        ui.settle(1)
        let tabCount = ui.tabTitles.count
        ui.highlightRows[0].doubleClick()
        ui.settle(1.5)
        XCTAssertEqual(ui.tabTitles.count, tabCount, "Double-click opened a second tab: \(ui.tabTitles)")
        XCTAssertTrue(
            ui.waitUntil(timeout: 5) { ui.selectedTabTitle == Sample.gradient },
            "Double-click didn't select the open Gradient tab; selected: \(String(describing: ui.selectedTabTitle))."
        )
    }

    /// T73: with no Google configuration (CI, in-memory library) "Export Selection…" explains why instead of exporting.
    @MainActor
    func testExportSelectionShowsTheNotConfiguredAlert() {
        let ui = launchBrowser()
        selectRows(ui, count: 2)
        expectSelected(ui, 2)
        ui.app.buttons["Export selection"].click()
        XCTAssertTrue(
            ui.staticText(containing: "Google export not configured.").waitForExistence(timeout: 5),
            "No \"Google export not configured.\" alert."
        )
        ui.attachScreenshot("Export selection alert", to: self)
        ui.alertButton("OK").click()
        XCTAssertTrue(
            ui.waitUntil { !ui.staticText(containing: "Google export not configured.").exists },
            "OK didn't close the alert."
        )
        expectSelected(ui, 2)
        expectCount(ui, Self.total, "The count changed after the alert.")
    }

    @MainActor
    private func assertBrowserUnchanged(_ ui: StudyReaderUI, total: Int, windows: Int, open: XCUIElement) {
        XCTAssertEqual(ui.app.windows.count, windows, "Return or Escape opened or closed a window.")
        XCTAssertFalse(ui.card(Sample.lecture).exists, "The library appeared after Return or Escape.")
        XCTAssertEqual(rows(in: ui).count, total, "The browser list changed after Return or Escape.")
        XCTAssertTrue(open.exists, "The row was deselected by Return or Escape (the detail pane is gone).")
    }
}
