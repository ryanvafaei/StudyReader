import XCTest

/// Selectors for the global search results, the PDF find bar and the reader page field (T88).
extension StudyReaderUI {
    @MainActor
    var searchField: XCUIElement { app.searchFields.firstMatch }

    /// Result rows of the global search. kind: "document", "highlight" or "note".
    @MainActor
    func searchHits(_ kind: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "search-hit-\(kind)")
    }

    @MainActor
    var pageField: XCUIElement { app.textFields["Page number"] }

    @MainActor
    var pageNumber: String { pageField.value as? String ?? "" }

    @MainActor
    var findField: XCUIElement { app.textFields["Find in document"] }

    /// The find bar's "n of m" / "No matches" text. The text carries the accessibility label "Match count"; macOS may
    /// expose the visible text as the value, so the value wins when it isn't the label itself.
    @MainActor
    var matchCountText: String {
        let element = app.staticTexts.matching(NSPredicate(format: "label == 'Match count' OR value == 'Match count'")).firstMatch
        if element.exists {
            let value = element.value as? String ?? ""
            if !value.isEmpty, value != "Match count" { return value }
        }
        let status = app.staticTexts.matching(
            NSPredicate(format: "value MATCHES '^[0-9]+ of [0-9]+$' OR value == 'No matches' OR label MATCHES '^[0-9]+ of [0-9]+$' OR label == 'No matches'")
        ).firstMatch
        return status.exists ? text(of: status) : ""
    }

    /// Static text whose label or value equals `text`.
    @MainActor
    func staticText(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", text, text)).firstMatch
    }

    /// Static text whose label or value contains `text`.
    @MainActor
    func staticText(containing text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)).firstMatch
    }
}
