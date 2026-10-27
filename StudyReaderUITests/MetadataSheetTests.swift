import XCTest

private typealias Sample = StudyReaderUI.Sample

/// T52 checkpoint, library steps 11–16: the metadata sheet (T50) and its tag field (T49).
final class MetadataSheetTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    private func openSheet(for title: String, in ui: StudyReaderUI) -> XCUIElement {
        ui.card(title).click()
        ui.settle() // the selection must reach the menu commands before the shortcut is typed
        ui.app.typeKey("m", modifierFlags: [.command, .shift])
        let sheet = ui.sheet
        XCTAssertTrue(sheet.textFields["Title"].waitForExistence(timeout: 5), "The metadata sheet didn't open.")
        // The fields load asynchronously; wait until the title is filled in.
        ui.waitUntil { (sheet.textFields["Title"].value as? String)?.isEmpty == false }
        return sheet
    }

    /// Escape in the sheet closes only the sheet. The sheet takes the key, so the library's Clear Selection doesn't run.
    @MainActor
    func testEscapeClosesTheSheetAndKeepsTheLibrarySelection() {
        let ui = StudyReaderUI.launch()
        let sheet = openSheet(for: Sample.sparse, in: ui)
        ui.app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3), "Escape didn't close the metadata sheet.")
        ui.settle()
        XCTAssertTrue(
            ui.menuItemState("File", "Edit Metadata…").enabled,
            "Escape in the sheet also cleared the library selection."
        )
    }

    /// Step 11: menu item disabled with nothing selected; ⇧⌘M and the context menu open the sheet.
    @MainActor
    func testEditMetadataIsDisabledWithoutSelectionAndOpensFromShortcutAndContextMenu() {
        let ui = StudyReaderUI.launch()
        let state = ui.menuItemState("File", "Edit Metadata…")
        XCTAssertTrue(state.exists)
        XCTAssertFalse(state.enabled, "Edit Metadata… is enabled with nothing selected.")

        let sheet = openSheet(for: Sample.sparse, in: ui)
        sheet.buttons["Cancel"].click()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3))

        ui.card(Sample.lecture).rightClick()
        // The File menu has an "Edit Metadata…" item too; the open context menu holds the one that's hittable.
        let contextItem = ui.app.menuItems.matching(identifier: "Edit Metadata…").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(contextItem, "The context menu has no Edit Metadata… item.")
        contextItem?.click()
        XCTAssertTrue(ui.sheet.textFields["Title"].waitForExistence(timeout: 5), "Context menu Edit Metadata… didn't open the sheet.")
        ui.sheet.buttons["Cancel"].click()
    }

    /// Step 12: Save updates the card; Cancel discards title, author and category, but tag changes save immediately.
    @MainActor
    func testSaveUpdatesTheCardAndCancelKeepsOnlyTagChanges() {
        let ui = StudyReaderUI.launch()
        var sheet = openSheet(for: Sample.sparse, in: ui)
        ui.replaceText(in: sheet.textFields["Title"], with: "Sparse edited")
        ui.replaceText(in: sheet.textFields["Author"], with: "Test Author")
        sheet.popUpButtons["Category"].click()
        ui.app.menuItems["Notes"].click()
        sheet.buttons["Save metadata"].click()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))

        let edited = ui.card("Sparse edited")
        XCTAssertTrue(edited.waitForExistence(timeout: 5), "The card didn't show the new title.")
        XCTAssertTrue(ui.text(of: edited).contains("Test Author"), "Card text: \(ui.text(of: edited))")
        XCTAssertTrue(ui.text(of: edited).contains("Notes"), "Card text: \(ui.text(of: edited))")

        sheet = openSheet(for: "Sparse edited", in: ui)
        ui.replaceText(in: sheet.textFields["Title"], with: "Should not be saved")
        let tagField = sheet.textFields["Add tag"]
        tagField.click()
        tagField.typeText("Kept\n")
        XCTAssertTrue(sheet.buttons["Remove tag Kept"].waitForExistence(timeout: 3))
        sheet.buttons["Cancel"].click()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))

        XCTAssertFalse(ui.card("Should not be saved").exists, "Cancel saved the title.")
        XCTAssertTrue(ui.card("Sparse edited").exists)
        sheet = openSheet(for: "Sparse edited", in: ui)
        XCTAssertTrue(sheet.buttons["Remove tag Kept"].exists, "The tag added before Cancel wasn't kept.")
        sheet.buttons["Cancel"].click()
    }

    /// Step 13.
    @MainActor
    func testBlankTitleShowsAnInlineErrorAndKeepsTheSheetOpen() {
        let ui = StudyReaderUI.launch()
        let sheet = openSheet(for: Sample.sparse, in: ui)
        let title = sheet.textFields["Title"]
        title.click()
        title.typeKey("a", modifierFlags: .command)
        title.typeKey(.delete, modifierFlags: [])
        sheet.buttons["Save metadata"].click()
        XCTAssertTrue(sheet.staticTexts["A title is required."].waitForExistence(timeout: 3))
        XCTAssertTrue(sheet.exists, "The sheet closed with a blank title.")
        ui.attachScreenshot("Step 13 blank title", to: self)
        sheet.buttons["Cancel"].click()
    }

    /// Step 14: Image… sets the cover and the card shows it; Reset Cover goes back to the first page.
    /// At the T52 checkpoint the card kept the old cover until the grid was rebuilt (switching to List and back).
    @MainActor
    func testChooseImageAndResetCoverUpdateTheCardCover() throws {
        let png = try TestFiles.redPNG(in: try TestFiles.folder())
        let ui = StudyReaderUI.launch()
        ui.enlargeWindow()
        let before = ScreenPixels.stats(of: ui.coverRect(of: Sample.sparse).insetBy(dx: 10, dy: 10))
        XCTAssertFalse(before?.isMostlyRed ?? true)

        var sheet = openSheet(for: Sample.sparse, in: ui)
        sheet.buttons["Choose cover image"].click()
        let panelShown = ui.waitUntil(timeout: 5) { ui.app.sheets.count > 1 || ui.app.dialogs.count > 0 }
        guard panelShown else {
            sheet.buttons["Cancel"].click()
            throw XCTSkip("The open panel isn't reachable from XCUITest; the ui-tester's Peekaboo pass covers step 14.")
        }
        ui.attachScreenshot("Step 14 open panel", to: self)
        // The panel is a sheet of its own (identifier "open-panel"); Go to Folder is a nested sheet ("GoToWindow").
        ui.app.typeKey("g", modifierFlags: [.command, .shift])
        let pathField = ui.app.sheets["GoToWindow"].textFields["PathTextField"]
        XCTAssertTrue(pathField.waitForExistence(timeout: 5), "The Go to Folder sheet didn't open.")
        pathField.typeText(png.path)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        // Go: selects the file in the panel. The main Return key isn't taken by this sheet from XCUITest, but the
        // keypad Enter is.
        let goneAfter: (XCUIKeyboardKey, XCUIElement.KeyModifierFlags) -> Bool = { key, flags in
            pathField.typeKey(key, modifierFlags: flags)
            return ui.app.sheets["GoToWindow"].waitForNonExistence(timeout: 1.5)
        }
        _ = goneAfter(.enter, []) || goneAfter(.return, []) || goneAfter(.return, .command)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        ui.attachScreenshot("Step 14 after go to folder", to: self)
        let openButton = ui.app.sheets["open-panel"].buttons["OKButton"]
        if openButton.exists, openButton.isEnabled { openButton.click() }
        XCTAssertTrue(
            ui.waitUntil(timeout: 5) { ui.app.sheets.count == 1 && ui.app.dialogs.count == 0 },
            "The open panel stayed open. Sheets: \(ui.app.sheets.count), dialogs: \(ui.app.dialogs.count)"
        )
        sheet.buttons["Save metadata"].click()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))

        let red = ui.waitUntil(timeout: 5) {
            ScreenPixels.stats(of: ui.coverRect(of: Sample.sparse).insetBy(dx: 10, dy: 10))?.isMostlyRed == true
        }
        ScreenPixels.attach(ui.coverRect(of: Sample.sparse), named: "Step 14 cover after Image…", to: self)
        XCTAssertTrue(red, "The card didn't show the chosen image after Save.")

        sheet = openSheet(for: Sample.sparse, in: ui)
        sheet.buttons["Reset cover to automatic"].click()
        sheet.buttons["Save metadata"].click()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        let reset = ui.waitUntil(timeout: 5) {
            ScreenPixels.stats(of: ui.coverRect(of: Sample.sparse).insetBy(dx: 10, dy: 10))?.isMostlyRed == false
        }
        ScreenPixels.attach(ui.coverRect(of: Sample.sparse), named: "Step 14 cover after Reset Cover", to: self)
        XCTAssertTrue(reset, "The card didn't go back to the first page after Reset Cover.")
    }

    /// Step 15: "Use Current Page" appears only when the sheet is opened from a reader.
    @MainActor
    func testUseCurrentPageIsHiddenInTheLibrary() {
        let ui = StudyReaderUI.launch()
        let sheet = openSheet(for: Sample.lecture, in: ui)
        XCTAssertFalse(sheet.buttons["Use current page as cover"].exists)
        sheet.buttons["Cancel"].click()
    }

    /// Step 16: suggestions appear while typing, ↓ moves the highlight, Return adds the highlighted suggestion,
    /// and "#Exam" reuses "Exam". At the T52 checkpoint Return added the typed text ("Sa") instead of the
    /// highlighted suggestion, which also created a stray tag.
    @MainActor
    func testTagFieldSuggestionsArrowKeysAndReturn() {
        let ui = StudyReaderUI.launch()
        let sheet = openSheet(for: Sample.sparse, in: ui)
        let field = sheet.textFields["Add tag"]
        field.click()
        field.typeText("Sample")

        let firstSuggestion = sheet.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add tag '")).firstMatch
        XCTAssertTrue(firstSuggestion.waitForExistence(timeout: 3), "No suggestions appeared while typing.")
        let suggestedName = String(firstSuggestion.label.dropFirst("Add tag ".count))
        ui.attachScreenshot("Step 16 suggestions", to: self)

        field.typeKey(.downArrow, modifierFlags: [])
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            sheet.buttons["Remove tag \(suggestedName)"].waitForExistence(timeout: 3),
            "Return didn't add the highlighted suggestion \"\(suggestedName)\"."
        )
        XCTAssertFalse(sheet.buttons["Remove tag Sample"].exists, "Return added the typed text instead of the suggestion.")

        field.click()
        field.typeText("Exam\n")
        field.typeText("#Exam\n")
        let examChips = sheet.buttons.matching(NSPredicate(format: "label == 'Remove tag Exam'"))
        XCTAssertEqual(examChips.count, 1, "\"#Exam\" didn't reuse \"Exam\".")
        XCTAssertFalse(sheet.buttons["Remove tag #Exam"].exists)
        sheet.buttons["Cancel"].click()
    }
}
