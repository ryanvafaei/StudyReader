import XCTest

private typealias Sample = StudyReaderUI.Sample

/// T52 checkpoint, sidebar Categories steps 21–25 (T50).
final class CategoryManagerTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    private func createCategory(_ name: String, in ui: StudyReaderUI) {
        ui.showSection("Categories")
        ui.newCategoryButton.click()
        let field = ui.sheet.textFields["Category name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText(name)
        ui.sheet.buttons["Add"].click()
        XCTAssertTrue(categoryRow(name, in: ui).waitForExistence(timeout: 8), "\(name) wasn't created.")
    }

    /// A category row is one combined static text: "<name>, [Built-in category, ]<N documents>".
    @MainActor
    private func categoryRow(_ name: String, in ui: StudyReaderUI) -> XCUIElement {
        let prefix = name + ","
        return ui.app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", prefix, prefix)).firstMatch
    }

    /// Step 21: built-ins show a lock and have no Rename or Delete.
    @MainActor
    func testBuiltInCategoriesAreLockedWithoutRenameOrDelete() {
        let ui = StudyReaderUI.launch()
        ui.showSection("Categories")
        XCTAssertTrue(categoryRow("Paper", in: ui).waitForExistence(timeout: 8))
        let locks = ui.app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Built-in category' OR value CONTAINS 'Built-in category'"))
        XCTAssertEqual(locks.count, 5, "Expected a lock on each of the five built-in categories.")
        categoryRow("Paper", in: ui).rightClick()
        XCTAssertFalse(ui.app.menuItems["Rename…"].waitForExistence(timeout: 1))
        XCTAssertFalse(ui.app.menuItems["Delete…"].exists)
        ui.app.typeKey(.escape, modifierFlags: [])
    }

    /// Steps 22–24: create, rename, assign a document, delete (its document moves to Other).
    @MainActor
    func testCreateRenameAssignAndDeleteACategory() {
        let ui = StudyReaderUI.launch()
        createCategory("Lab reports", in: ui)
        let created = ui.text(of: categoryRow("Lab reports", in: ui))
        XCTAssertTrue(created.contains("0 documents"), "Row text: \(created)")

        categoryRow("Lab reports", in: ui).rightClick()
        ui.app.menuItems["Rename…"].click()
        ui.replaceText(in: ui.sheet.textFields["Category name"], with: "Lab reports 2")
        ui.sheet.buttons["Rename"].click()
        XCTAssertTrue(categoryRow("Lab reports 2", in: ui).waitForExistence(timeout: 8))

        ui.showSection("Library")
        ui.card(Sample.gradient).click()
        ui.settle() // the selection must reach the menu commands before the shortcut is typed
        ui.app.typeKey("m", modifierFlags: [.command, .shift])
        XCTAssertTrue(ui.sheet.popUpButtons["Category"].waitForExistence(timeout: 5))
        ui.sheet.popUpButtons["Category"].click()
        ui.app.menuItems["Lab reports 2"].click()
        ui.sheet.buttons["Save metadata"].click()

        ui.showSection("Categories")
        XCTAssertTrue(
            ui.waitUntil { ui.text(of: categoryRow("Lab reports 2", in: ui)).contains("1 document") },
            "The count didn't become 1 document: \(ui.text(of: categoryRow("Lab reports 2", in: ui)))"
        )

        categoryRow("Lab reports 2", in: ui).rightClick()
        ui.app.menuItems["Delete…"].click()
        // At the T52 checkpoint the message read "Its 1 document move to Other." (no plural agreement).
        XCTAssertTrue(
            ui.app.staticTexts["Its 1 document moves to Other."].waitForExistence(timeout: 3),
            "Delete confirmation text is wrong."
        )
        ui.attachScreenshot("Step 24 delete confirmation", to: self)
        ui.confirmDelete()
        XCTAssertTrue(categoryRow("Lab reports 2", in: ui).waitForNonExistence(timeout: 5))

        ui.showSection("Library")
        let card = ui.card(Sample.gradient)
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        XCTAssertTrue(ui.text(of: card).contains("Other"), "The document didn't move to Other. Card text: \(ui.text(of: card))")
    }

    /// Step 25: deleting the default category resets Settings to Lecture slides.
    @MainActor
    func testDeletingTheDefaultCategoryResetsSettingsToLectureSlides() {
        let ui = StudyReaderUI.launch()
        createCategory("Temp default", in: ui)

        ui.app.typeKey(",", modifierFlags: .command)
        let picker = ui.app.popUpButtons["Default category for imports"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.click()
        ui.app.menuItems["Temp default"].click()
        XCTAssertEqual(picker.value as? String, "Temp default")
        ui.app.typeKey("w", modifierFlags: .command)

        categoryRow("Temp default", in: ui).rightClick()
        ui.app.menuItems["Delete…"].click()
        ui.confirmDelete()
        XCTAssertTrue(categoryRow("Temp default", in: ui).waitForNonExistence(timeout: 5))

        ui.app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "Lecture slides")
        ui.app.typeKey("w", modifierFlags: .command)
    }
}
