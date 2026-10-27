import AppKit
import XCTest

/// Highlight colours as they look after the 0.35 alpha band is drawn over a white page or text background
/// (`HighlightPalette`: alpha 0.35 over white). Used for pixel counts; the tolerance absorbs colour management.
enum BandColor {
    case yellow, green, blue, pink

    var blended: (red: Double, green: Double, blue: Double) {
        switch self {
        case .yellow: (1.0, 0.9475, 0.72)
        case .green: (0.79, 0.93, 0.79)
        case .blue: (0.7725, 0.8775, 1.0)
        case .pink: (1.0, 0.8075, 0.8775)
        }
    }

    static let tolerance = 0.05
}

extension StudyReaderUI {
    /// Panel rows (accessibility identifier "highlight-row"), top to bottom.
    var highlightRows: [XCUIElement] {
        app.descendants(matching: .any).matching(identifier: "highlight-row").allElementsBoundByIndex
            .filter { $0.exists }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    /// Everything one row exposes as text: its label, value and the text of its descendants.
    func rowText(_ row: XCUIElement) -> String {
        var parts = [row.label, row.value as? String ?? ""]
        for child in row.descendants(matching: .staticText).allElementsBoundByIndex {
            parts.append(child.label)
            parts.append(child.value as? String ?? "")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " | ")
    }

    /// Opens a document from the library and waits for its reader tab.
    func openDocument(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        card(title).doubleClick()
        XCTAssertTrue(
            waitUntil { tabTitles.contains(title) },
            "The reader tab didn't open. Tabs: \(tabTitles)",
            file: file,
            line: line
        )
    }

    /// Opens the inspector on its Highlights tab.
    func showHighlightsPanel() {
        if !isInspectorOpen {
            inspectorToggle.click()
            _ = waitUntil { isInspectorOpen }
        }
        app.radioButtons["Highlights"].click()
        settle(0.5)
    }

    /// Waits until the panel lists `count` rows.
    @discardableResult
    func waitForRows(_ count: Int, timeout: TimeInterval = 8) -> Bool {
        waitUntil(timeout: timeout) { highlightRows.count == count }
    }

    /// The reader area in screen points: the front window minus the toolbar and, when the panel lists rows, minus the
    /// inspector. Keeps toolbar swatches and the panel's opaque colour bars out of pixel counts.
    var readerRect: CGRect {
        let window = app.windows.firstMatch.frame
        var rect = CGRect(x: window.minX, y: window.minY + 90, width: window.width, height: window.height - 90)
        if isInspectorOpen, let first = highlightRows.first {
            rect.size.width = max(0, first.frame.minX - 8 - rect.minX)
        }
        return rect
    }

    /// Pixels of `color`'s band in the reader area.
    func bandPixels(_ color: BandColor) -> Int {
        ScreenPixels.count(near: color.blended, tolerance: BandColor.tolerance, in: readerRect) ?? -1
    }

    /// Waits up to `timeout` for at least `minimum` pixels of the band; returns the last count.
    @discardableResult
    func waitForBand(_ color: BandColor, atLeast minimum: Int = 100, timeout: TimeInterval = 5) -> Int {
        var last = 0
        _ = waitUntil(timeout: timeout) {
            last = bandPixels(color)
            return last >= minimum
        }
        return last
    }

    /// Chooses the current highlight colour from the toolbar menu by its label (persists between launches, OB1).
    func chooseHighlightColor(_ label: String) {
        highlightColorMenu.click()
        let item = app.menuItems[label]
        if item.waitForExistence(timeout: 3) {
            item.click()
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }
        settle(0.5)
    }

    /// Clicks an empty spot of the reader (below the text, or on the page margin) so the reader has keyboard focus.
    func clickBlankReaderArea() {
        let window = app.windows.firstMatch
        let rect = readerRect
        let point = CGVector(dx: rect.midX - window.frame.minX, dy: rect.minY + rect.height * 0.92 - window.frame.minY)
        window.coordinate(withNormalizedOffset: .zero).withOffset(point).click()
        settle(0.5)
    }
}
