import XCTest

/// Helpers for the daily review UI tests (T112). Identifiers come from `Features/Review/` (T109, T110).
extension StudyReaderUI {
    /// Any element with this accessibility identifier.
    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// The sidebar row for `identifier`: the outline row that contains the labelled element.
    func sidebarRow(_ identifier: String) -> XCUIElement {
        sidebar.outlineRows.containing(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    /// The row's cell (the row itself reports "Disabled" in the hierarchy).
    func sidebarCell(_ identifier: String) -> XCUIElement {
        sidebar.cells.containing(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    /// Whether the sidebar row is selected: `isSelected` of its outline row or its cell (AXSelected), or value 1.
    func isSidebarRowSelected(_ identifier: String) -> Bool {
        let row = sidebarRow(identifier)
        let cell = sidebarCell(identifier)
        return (row.exists && row.isSelected) || (cell.exists && cell.isSelected) || "\(row.value ?? "")" == "1" || "\(cell.value ?? "")" == "1"
    }

    /// One line per sidebar row: identifier and the selected state of its row and cell, plus the window title.
    var sidebarSelectionReport: String {
        let ids = sidebar.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'sidebar-'")).allElementsBoundByIndex.map(\.identifier)
        let rows = ids.map { id in
            "\(id): row.isSelected=\(sidebarRow(id).isSelected) cell.isSelected=\(sidebarCell(id).isSelected)"
        }
        return "Window title: \(app.windows.firstMatch.title). " + rows.joined(separator: "; ")
    }

    /// Selects a sidebar row by its identifier (for example "sidebar-review") and asserts that the row became selected.
    /// Tries a click on the left of the row's cell (away from the badge), then the keyboard: click the first row and
    /// press Down once per row above the target. The attempts and the selection of every row go to the test log.
    @discardableResult
    func showSection(identifier: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let labels = sidebar.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'sidebar-'")).allElementsBoundByIndex
        guard let index = labels.firstIndex(where: { $0.identifier == identifier }), let first = labels.first else {
            XCTFail("No sidebar element with identifier \(identifier).", file: file, line: line)
            return false
        }
        var log = ["Before: " + sidebarSelectionReport]
        sidebarCell(identifier).coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).click()
        var selected = waitUntil(timeout: 3) { self.isSidebarRowSelected(identifier) }
        log.append("After cell click: selected=\(selected). " + sidebarSelectionReport)
        if !selected {
            first.click()
            settle(1)
            for _ in 0..<index {
                app.typeKey(.downArrow, modifierFlags: [])
                settle(0.3)
            }
            selected = waitUntil(timeout: 3) { self.isSidebarRowSelected(identifier) }
            log.append("After keyboard: selected=\(selected). " + sidebarSelectionReport)
        }
        XCTContext.runActivity(named: "Sidebar selection for \(identifier)") { activity in
            let note = XCTAttachment(string: log.joined(separator: "\n"))
            note.name = "Sidebar selection log"
            note.lifetime = .keepAlways
            activity.add(note)
        }
        XCTAssertTrue(selected, "Sidebar row \(identifier) is not selected. " + log.joined(separator: " | "), file: file, line: line)
        return selected
    }

    /// Selects the sidebar "Review" section and waits for the start screen, the empty state, the retry state or the
    /// loading spinner. On timeout it attaches the hierarchy, a screenshot and a note naming the state it saw.
    func showReview(file: StaticString = #filePath, line: UInt = #line) {
        let states = ["review-start", "review-empty", "review-retry", "review-loading"]
        func seen() -> [String] { states.filter { element($0).exists } }
        showSection(identifier: "sidebar-review", file: file, line: line)
        let appeared = waitUntil(timeout: 10) { !seen().isEmpty }
        guard appeared else {
            let selected = isSidebarRowSelected("sidebar-review")
            let note = "Review state seen: none of \(states.joined(separator: ", ")). Sidebar row selected: \(selected)."
            attachDiagnostics(note, file: file, line: line)
            return
        }
        // The loading spinner is transient; give it a moment to turn into the start or empty state.
        if seen() == ["review-loading"] {
            let resolved = waitUntil(timeout: 10) { self.element("review-start").exists || self.element("review-empty").exists || self.element("review-retry").exists }
            if !resolved {
                attachDiagnostics("Review state seen: review-loading stuck for 10 s. Sidebar row selected: \(isSidebarRowSelected("sidebar-review")).", file: file, line: line)
                return
            }
        }
        if element("review-retry").exists {
            attachDiagnostics("Review state seen: review-retry (the plan failed to load). Sidebar row selected: \(isSidebarRowSelected("sidebar-review")).", file: file, line: line)
        }
    }

    private func attachDiagnostics(_ note: String, file: StaticString, line: UInt) {
        XCTContext.runActivity(named: "Review state: \(note)") { activity in
            let text = XCTAttachment(string: note + "\n\n" + app.debugDescription)
            text.name = "Review hierarchy and state"
            text.lifetime = .keepAlways
            activity.add(text)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "Review screenshot"
            shot.lifetime = .keepAlways
            activity.add(shot)
        }
        XCTFail(note, file: file, line: line)
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
