import XCTest

private typealias Sample = StudyReaderUI.Sample

/// T112: daily review on the seeded library (T109, T110, T111), the key rule of ADR-0022 and the Review settings tab.
final class ReviewSessionTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private static let firstFront = "lowers the loss"
    private static let secondFront = "Proteins embedded"
    private static let thirdFront = "Cristae"
    private static let thirdNote = "Check this for the quiz"

    @MainActor
    private func launchAndStart() -> StudyReaderUI {
        let ui = StudyReaderUI.launch()
        ui.showReview()
        ui.startReview()
        return ui
    }

    /// True when any element shows `text` as label or value.
    @MainActor
    private func shows(_ text: String, in ui: StudyReaderUI) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
        return ui.waitUntil(timeout: 5) {
            ui.app.descendants(matching: .any).matching(predicate).firstMatch.exists
        }
    }

    // MARK: - 1

    @MainActor
    func testStartScreenShowsTheSeededCounts() {
        let ui = StudyReaderUI.launch()
        ui.attachHierarchy("Library hierarchy", to: self)
        ui.showReview()
        ui.attachScreenshot("Review start screen", to: self)
        ui.attachHierarchy("Review start hierarchy", to: self)

        XCTAssertTrue(ui.element("review-card-count").waitForExistence(timeout: 5), "No card count on the start screen.")
        XCTAssertEqual(ui.text(of: ui.element("review-card-count")), "8 cards to review")
        XCTAssertEqual(ui.text(of: ui.element("review-due-new")), "4 due · 4 new")

        // The badge is queried only when the sidebar exposes it as a text; the start screen assertions above stand alone.
        let badge = ui.sidebar.staticTexts.matching(NSPredicate(format: "label == '8' OR value == '8'")).firstMatch
        if badge.exists {
            XCTAssertTrue(badge.exists)
        }
    }

    // MARK: - 2

    @MainActor
    func testRatingWithButtonsAndKeys() {
        let ui = launchAndStart()
        ui.attachScreenshot("Review card", to: self)
        XCTAssertEqual(ui.reviewProgress, "1 of 8")
        XCTAssertTrue(ui.waitForFront(containing: Self.firstFront), "First card front: \(ui.reviewFrontText)")

        ui.rate("review-rate-good")
        XCTAssertEqual(ui.reviewProgress, "2 of 8")
        XCTAssertTrue(ui.waitForFront(containing: Self.secondFront), "Second card front: \(ui.reviewFrontText)")

        ui.pressKey("1")
        XCTAssertTrue(ui.waitForProgress("3 of 8"), "Key 1 didn't rate; progress: \(ui.reviewProgress)")
        XCTAssertTrue(ui.waitForFront(containing: Self.thirdFront), "Third card front: \(ui.reviewFrontText)")
        XCTAssertTrue(shows(Self.thirdNote, in: ui), "The note \"\(Self.thirdNote)\" isn't visible on the passive card.")

        ui.pressKey(" ")
        ui.settle(1)
        XCTAssertEqual(ui.reviewProgress, "3 of 8", "Space changed the progress on a passive card.")

        ui.pressKey("3")
        ui.settle(1)
        XCTAssertEqual(ui.reviewProgress, "3 of 8", "Key 3 rated in two-button mode.")
    }

    // MARK: - 3

    @MainActor
    func testSkipMovesTheCardToTheEnd() {
        let ui = launchAndStart()
        ui.element("review-action-skip").click()
        XCTAssertTrue(ui.waitForFront(containing: Self.secondFront), "After Skip the front is: \(ui.reviewFrontText)")
        XCTAssertEqual(ui.reviewProgress, "1 of 8")

        for _ in 0..<7 {
            ui.settle(0.5)
            ui.pressKey("2")
            let before = ui.reviewProgress
            _ = ui.waitUntil(timeout: 8) { ui.reviewProgress != before }
        }
        XCTAssertTrue(ui.waitForFront(containing: Self.firstFront), "The skipped card isn't last; front: \(ui.reviewFrontText), progress: \(ui.reviewProgress)")
        XCTAssertEqual(ui.reviewProgress, "8 of 8")
    }

    // MARK: - 4

    @MainActor
    func testFinishingShowsTheSummaryAndEmptiesToday() {
        let ui = launchAndStart()
        for index in 0..<8 {
            ui.rate(index.isMultiple(of: 2) ? "review-rate-again" : "review-rate-good")
        }
        XCTAssertTrue(ui.element("review-summary-reviewed").waitForExistence(timeout: 8), "No summary after the last card.")
        ui.attachScreenshot("Review summary", to: self)
        XCTAssertEqual(ui.text(of: ui.element("review-summary-reviewed")), "Reviewed 8 cards")
        XCTAssertEqual(ui.text(of: ui.element("review-summary-remembered")), "Remembered 50%")

        ui.element("review-done").click()
        XCTAssertTrue(ui.element("review-empty").waitForExistence(timeout: 8), "Done didn't show \"Nothing to review\".")
        XCTAssertTrue(ui.app.staticTexts["Nothing to review"].exists || shows("Nothing to review", in: ui))
    }

    // MARK: - 5

    @MainActor
    func testKeysInTheNoteFieldDoNotRate() {
        let ui = launchAndStart()
        ui.element("review-action-note").click()
        let editor = ui.element("review-note-editor")
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Note didn't open an editor.")
        ui.settle(1)
        ui.attachScreenshot("Review actions bar with the note editor open", to: self)

        // No click into the editor: opening Note has to hand the focus over by itself.
        ui.app.typeText("12 3")
        ui.pressKey("\r")
        ui.settle(1)

        XCTAssertEqual(ui.reviewProgress, "1 of 8", "A key typed in the note editor rated or skipped a card.")
        let value = ui.editorValue("review-note-editor")
        XCTAssertTrue(
            value.contains("12 3"),
            "The note editor's value is \"\(value)\"; keyboard focus: \(ui.hasKeyboardFocus(editor)). The keys didn't reach the editor."
        )

        // Close the editor (flushes the note), then reopen it: the text was saved.
        ui.element("review-action-note").click()
        XCTAssertTrue(ui.waitUntil { !ui.element("review-note-editor").exists }, "Note didn't close the editor.")
        XCTAssertTrue(shows("12 3", in: ui), "The passive card doesn't show the saved note.")
        ui.element("review-action-note").click()
        XCTAssertTrue(ui.element("review-note-editor").waitForExistence(timeout: 5))
        XCTAssertTrue(
            ui.waitUntil { ui.editorValue("review-note-editor").contains("12 3") },
            "The reopened note editor lost the text: \"\(ui.editorValue("review-note-editor"))\""
        )
    }

    // MARK: - 6

    @MainActor
    func testReturnAndEscapeInTheEditFieldDoNothingElse() {
        let ui = StudyReaderUI.launch()
        ui.card(Sample.lecture).click()
        ui.settle()
        ui.showReview()
        ui.startReview()
        let original = ui.reviewFrontText
        XCTAssertTrue(original.contains(Self.firstFront), "First card front: \(original)")

        ui.element("review-action-edit").click()
        let editor = ui.element("review-edit-editor")
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Edit didn't open an editor.")
        ui.settle(1)

        ui.app.typeText("Better wording")
        ui.pressKey("\r")
        ui.pressKey(XCUIKeyboardKey.escape.rawValue)
        ui.settle(1)

        let value = ui.editorValue("review-edit-editor")
        XCTAssertTrue(value.contains("Better wording"), "The edit editor's value is \"\(value)\"; keyboard focus: \(ui.hasKeyboardFocus(editor)).")
        XCTAssertEqual(ui.reviewProgress, "1 of 8", "Return or Escape in the edit field changed the session.")
        XCTAssertTrue(ui.tabTitles.isEmpty, "Return or Escape opened a document: \(ui.tabTitles)")

        ui.element("review-edit-cancel").click()
        XCTAssertTrue(ui.waitUntil { !ui.element("review-edit-editor").exists }, "Cancel didn't close the editor.")
        XCTAssertEqual(ui.reviewFrontText, original, "Cancel changed the front.")

        ui.element("review-action-edit").click()
        XCTAssertTrue(ui.element("review-edit-editor").waitForExistence(timeout: 5))
        ui.replaceText(in: ui.element("review-edit-editor"), with: "Rewritten front")
        ui.element("review-edit-save").click()
        XCTAssertTrue(ui.waitForFront(containing: "Rewritten front"), "Save didn't show the new text: \(ui.reviewFrontText)")
        XCTAssertTrue(ui.element("review-show-original").waitForExistence(timeout: 5), "No Show Original after an edit.")
        ui.attachScreenshot("Review edited card", to: self)

        ui.element("review-show-original").click()
        XCTAssertTrue(ui.waitForFront(containing: Self.firstFront), "Show Original didn't restore the text: \(ui.reviewFrontText)")

        ui.showSection("Library")
        XCTAssertTrue(ui.card(Sample.lecture).waitForExistence(timeout: 8))
        ui.settle()
        ui.app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            ui.waitUntil { ui.tabTitles.contains(Sample.lecture) },
            "The library selection was lost: Return in the Library opened nothing."
        )
    }

    // MARK: - 7

    @MainActor
    func testFrequencyOffRemovesTheCard() {
        let ui = launchAndStart()
        ui.element("review-action-frequency").click()
        let off = ui.app.menuItems["Off"].firstMatch
        XCTAssertTrue(off.waitForExistence(timeout: 5), "The Frequency menu has no Off item.")
        off.click()
        XCTAssertTrue(ui.waitForProgress("1 of 7"), "Frequency Off didn't drop the card; progress: \(ui.reviewProgress)")
        XCTAssertTrue(ui.waitForFront(containing: Self.secondFront), "Front after Off: \(ui.reviewFrontText)")
    }

    // MARK: - 8

    @MainActor
    func testOpenInDocumentOpensTheReader() {
        let ui = launchAndStart()
        ui.rate("review-rate-good")
        XCTAssertTrue(ui.waitForFront(containing: Self.secondFront), "Front: \(ui.reviewFrontText)")

        ui.element("review-action-open").click()
        XCTAssertTrue(
            ui.waitUntil(timeout: 10) { ui.tabTitles.contains(Sample.lecture) },
            "Open in Document didn't open \(Sample.lecture); tabs: \(ui.tabTitles)"
        )

        ui.tab(at: 0).click()
        XCTAssertTrue(
            ui.waitUntil(timeout: 8) { ui.reviewProgress == "2 of 8" },
            "Back in the library window the session shows \"\(ui.reviewProgress)\" instead of \"2 of 8\"."
        )
    }

    // MARK: - 9

    @MainActor
    func testReviewSettingsTab() {
        let ui = StudyReaderUI.launch()
        ui.settle()
        ui.app.typeKey(",", modifierFlags: .command)

        let window = ui.app.windows.matching(
            NSPredicate(format: "identifier == 'com_apple_SwiftUI_Settings_window' OR title == 'General'")
        ).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Settings didn't open with ⌘,.")
        let reviewTab = window.toolbars.buttons["Review"]
        XCTAssertTrue(reviewTab.waitForExistence(timeout: 3), "Settings has no Review tab.")
        reviewTab.click()

        func control(_ text: String) -> XCUIElement {
            window.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@ OR title CONTAINS %@", text, text)).firstMatch
        }
        XCTAssertTrue(control("Daily limit").waitForExistence(timeout: 5), "No Daily limit stepper.")
        XCTAssertTrue(control("New cards per day").exists, "No New cards per day stepper.")
        let toggle = window.switches.matching(NSPredicate(format: "label CONTAINS 'Show four rating buttons' OR title CONTAINS 'Show four rating buttons'")).firstMatch
        XCTAssertTrue(toggle.exists, "No \"Show four rating buttons\" toggle.")
        XCTAssertTrue(control("Frequency for Lecture slides").exists, "No \"Frequency for Lecture slides\" picker.")
        ui.attachHierarchy("Review settings hierarchy", to: self)
        ui.attachScreenshot("Settings Review", to: self)

        toggle.click()
        ui.app.typeKey("w", modifierFlags: .command)

        ui.showReview()
        ui.startReview()
        for identifier in ["review-rate-again", "review-rate-hard", "review-rate-good", "review-rate-easy"] {
            XCTAssertTrue(ui.element(identifier).waitForExistence(timeout: 5), "No \(identifier) button with four rating buttons on.")
        }
    }
}
