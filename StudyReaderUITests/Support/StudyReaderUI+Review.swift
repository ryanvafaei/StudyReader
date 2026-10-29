import XCTest

/// Helpers for the daily review UI tests (T112). Identifiers come from `Features/Review/` (T109, T110).
extension StudyReaderUI {
    /// Any element with this accessibility identifier.
    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Selects the sidebar "Review" section and waits for the start screen or the empty state.
    func showReview(file: StaticString = #filePath, line: UInt = #line) {
        func shown() -> Bool { element("review-start").exists || element("review-empty").exists }
        showSection("Review")
        var appeared = waitUntil(timeout: 4) { shown() }
        if !appeared {
            // The first click on the row (its badge makes the text "Review, 8") may only focus the sidebar.
            let row = sidebar.cells.containing(.staticText, identifier: "Review").firstMatch
            if row.exists { row.click() }
            appeared = waitUntil(timeout: 10) { shown() }
        }
        XCTAssertTrue(appeared, "The Review section showed neither the start screen nor the empty state.", file: file, line: line)
    }

    /// "N of M" in the card header; empty when no card is showing.
    var reviewProgress: String {
        text(of: element("review-progress"))
    }

    /// The card front. A rich text view may report its text as label or value, so both are joined.
    var reviewFrontText: String {
        let front = element("review-card-front")
        guard front.exists else { return "" }
        return [front.label, front.value as? String ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Clicks a rating button (for example "review-rate-good") and waits for the progress text to change.
    func rate(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let before = reviewProgress
        let button = element(identifier)
        XCTAssertTrue(button.waitForExistence(timeout: 5), "No rating button \(identifier).", file: file, line: line)
        button.click()
        let changed = waitUntil(timeout: 8) { self.reviewProgress != before }
        XCTAssertTrue(changed, "Rating with \(identifier) didn't change the progress (still \"\(before)\").", file: file, line: line)
    }

    /// Types one key with no modifiers into the focused element.
    func pressKey(_ key: String) {
        app.typeKey(key, modifierFlags: [])
    }

    /// Clicks Start Review and waits for the first card.
    func startReview(file: StaticString = #filePath, line: UInt = #line) {
        let start = element("review-start")
        XCTAssertTrue(start.waitForExistence(timeout: 10), "No Start Review button.", file: file, line: line)
        start.click()
        let began = waitUntil(timeout: 10) { !self.reviewProgress.isEmpty }
        XCTAssertTrue(began, "Start Review didn't show a card.", file: file, line: line)
        // The card claims keyboard focus in the update after it appears.
        settle(1)
    }

    /// Waits until the card front contains `text`.
    @discardableResult
    func waitForFront(containing text: String, timeout: TimeInterval = 8) -> Bool {
        waitUntil(timeout: timeout) { self.reviewFrontText.contains(text) }
    }

    /// Waits until the progress reads `text`.
    @discardableResult
    func waitForProgress(_ text: String, timeout: TimeInterval = 8) -> Bool {
        waitUntil(timeout: timeout) { self.reviewProgress == text }
    }

    /// The text value of a text editor or text view element.
    func editorValue(_ identifier: String) -> String {
        element(identifier).value as? String ?? ""
    }
}
