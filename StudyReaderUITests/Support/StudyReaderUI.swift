import AppKit
import XCTest

/// Driver for the StudyReader UI tests (ADR-0019).
///
/// Every launch uses an in-memory library (ADR-0011): the `-StudyReaderInMemory` argument plus the
/// `STUDYREADER_IN_MEMORY` variable. The user's library is never opened.
///
/// Queries use the accessibility labels the views already set. On macOS a static text exposes its text as `value`, not
/// `label` (an explicit `.accessibilityLabel` on a combined text group shows up as the value too), so static-text
/// predicates check both. A grid card is one static text whose text starts with "<title>,"
/// (`LibraryItemFormat.accessibilityLabel`). The window tab bar is a tab group titled "tab bar";
/// each tab is a Tab element titled with its window title.
@MainActor
final class StudyReaderUI {
    static let bundleIdentifier = "com.ryanvafaei.StudyReader"
    /// No `-ApplePersistenceIgnoreState`: runs that passed it started with no window at all (suspected cause, 2026-10-26).
    /// `-NSQuitAlwaysKeepsWindows NO` keeps macOS from restoring the reader windows the previous test left open.
    static let inMemoryArguments = ["-StudyReaderInMemory", "-NSQuitAlwaysKeepsWindows", "NO"]

    /// Documents from Debug > Seed Sample Library (`SampleLibrary.swift`).
    enum Sample {
        /// PDF, category Lecture slides, author Dr. A. Rivera.
        static let lecture = "Sample · Lecture 1: Cell Biology"
        /// PDF, category Paper, author M. Chen, no tags.
        static let sparse = "Sample · Paper: Sparse Attention Study"
        /// Markdown, category Notes.
        static let gradient = "Sample · Notes: Gradient Descent"
        /// Markdown, text extraction failed.
        static let retrieval = "Sample · Paper: Retrieval Notes"
        /// Original file missing (no bookmark).
        static let pendulum = "Sample · Lab manual: Pendulum"
        /// 16:9 landscape PDF.
        static let membrane = "Sample · Slides: Membrane Transport"
    }

    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    /// Launches with an in-memory library and waits for the library window. Seeds the sample library unless `seed` is false.
    static func launch(seed: Bool = true, file: StaticString = #filePath, line: UInt = #line) -> StudyReaderUI {
        let app = XCUIApplication()
        app.launchArguments += inMemoryArguments
        app.launchEnvironment["STUDYREADER_IN_MEMORY"] = "1"
        app.launch()
        let ui = StudyReaderUI(app: app)
        ui.ensureLibraryWindow()
        guard ui.sidebar.exists else {
            // Stop here instead of letting every later query wait and fail; the screenshot shows what was on screen.
            ui.attachScreenshot("No library window after launch", to: nil)
            XCTFail("The library window didn't open, even from Window > StudyReader.", file: file, line: line)
            return ui
        }
        // Reader windows restored from an earlier run would cover the library or add stray tabs, so every launch
        // starts from the library window alone.
        ui.closeRestoredReaders()
        ui.ensureLibraryWindow()
        // The layout is a per-Mac setting that outlives the launch (ephemeral defaults suite), so a List test would
        // leave the next launch in List. Every launch starts in Grid.
        ui.setLayout("Grid")
        if seed {
            ui.seedSampleLibrary(file: file, line: line)
        }
        return ui
    }

    // MARK: - Waiting

    /// Opens the library window from Window > StudyReader when the launch (or a restored state) left none.
    func ensureLibraryWindow() {
        if sidebar.waitForExistence(timeout: 10) { return }
        let windowMenu = app.menuBars.menuBarItems["Window"]
        windowMenu.click()
        let libraryItem = windowMenu.menuItems["StudyReader"]
        if libraryItem.exists {
            libraryItem.click()
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }
        _ = sidebar.waitForExistence(timeout: 10)
    }

    /// Closes reader windows and tabs that macOS restored at launch (identifier "reader-…"), leaving the library.
    func closeRestoredReaders() {
        settle(1)
        for _ in 0..<6 {
            let readers = app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'reader'"))
            guard readers.count > 0 else { return }
            let window = readers.firstMatch
            let close = window.buttons[XCUIIdentifierCloseWindow]
            if close.exists { close.click() } else { app.typeKey("w", modifierFlags: .command) }
            settle(0.5)
        }
    }

    /// Lets SwiftUI publish a click's selection to the focused-value menu commands and key handlers.
    /// A shortcut or Return typed right after a click is dropped otherwise.
    func settle(_ seconds: TimeInterval = 1) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Polls `condition` until it's true or `timeout` passes. Returns the last result.
    @discardableResult
    func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    // MARK: - Library window

    var sidebar: XCUIElement { app.outlines.firstMatch }

    func showSection(_ title: String) {
        sidebar.staticTexts[title].click()
    }

    func seedSampleLibrary(file: StaticString = #filePath, line: UInt = #line) {
        menu("Debug", "Seed Sample Library")
        XCTAssertTrue(
            card(Sample.lecture).waitForExistence(timeout: 20),
            "Debug > Seed Sample Library didn't show the sample cards.",
            file: file,
            line: line
        )
    }

    /// Grid card: the text block whose combined accessibility label starts with "<title>,".
    func card(_ title: String) -> XCUIElement {
        let prefix = title + ","
        return app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", prefix, prefix)).firstMatch
    }

    /// The visible text of an element: its label, or its value when the label is empty (static texts on macOS).
    func text(of element: XCUIElement) -> String {
        element.label.isEmpty ? (element.value as? String ?? "") : element.label
    }

    /// List-view row, addressed by its title cell. SwiftUI's `Table` is exposed as an Outline of OutlineRows (like the
    /// sidebar), and the OutlineRow itself reports "not hittable", so tests click the title text inside the row.
    func row(_ title: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", title, title)).firstMatch
    }

    /// "Grid" or "List" (the layout segmented control in the library toolbar).
    func setLayout(_ layout: String) {
        app.toolbars.radioButtons[layout].click()
        // The new layout rebuilds the whole list; wait for it before querying rows.
        RunLoop.current.run(until: Date().addingTimeInterval(1))
    }

    /// The card's outer frame (cover, text and 8 pt padding), whatever the accessibility element reports. SwiftUI exposes
    /// the combined text block of most cards as the whole card (width = card width), but for a card with a progress
    /// row (e.g. "Retrieval Notes", 10 percent read) it reports only the text block, 16 pt narrower (`LibraryGridCard`).
    func cardFrame(of title: String) -> CGRect {
        let element = card(title).frame
        if element.height > element.width * 1.6 { return element }
        return element.insetBy(dx: -8, dy: 0)
    }

    /// The cover drawn at the top of a grid card. The cover is hidden from accessibility, so its rect is derived:
    /// the card minus its 8 pt padding, 3:4 portrait (`LibraryGridCard`, `DocumentCoverView`).
    func coverRect(of title: String) -> CGRect {
        let element = card(title).frame
        let width = element.width > 0 && element.height > element.width * 1.6 ? element.width - 16 : element.width
        let height = width * 4 / 3
        if element.height > element.width * 1.6 {
            return CGRect(x: element.minX + 8, y: element.minY + 8, width: width, height: height)
        }
        return CGRect(x: element.minX, y: element.minY - 8 - height, width: width, height: height)
    }

    /// Window > Fill when the menu has it, otherwise Window > Zoom, so the grid shows every sample card.
    func enlargeWindow() {
        let windowMenu = app.menuBars.menuBarItems["Window"]
        windowMenu.click()
        let fill = windowMenu.menuItems["Fill"]
        if fill.exists, fill.isEnabled {
            fill.click()
        } else {
            windowMenu.menuItems["Zoom"].click()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1))
    }

    // MARK: - Tabs

    /// The tab bar is a tab group titled "tab bar" inside the window; each tab is an element of type Tab whose title is
    /// the window title (value 1 on the selected tab, 0 on the others). It only exists while the window has 2+ tabs.
    var tabBar: XCUIElement {
        app.tabGroups.matching(NSPredicate(format: "title == 'tab bar'")).firstMatch
    }

    private func tabElements() -> [XCUIElement] {
        tabBar.tabs.allElementsBoundByIndex
    }

    /// Titles of the front window's tabs. Empty when the window shows no tab bar (a single window, no tabs).
    var tabTitles: [String] {
        guard tabBar.exists else { return [] }
        return tabElements().map { $0.title.isEmpty ? $0.label : $0.title }
    }

    func tab(_ title: String) -> XCUIElement {
        tabBar.tabs.matching(NSPredicate(format: "title == %@ OR label == %@", title, title)).firstMatch
    }

    func tab(at index: Int) -> XCUIElement {
        tabBar.tabs.element(boundBy: index)
    }

    var selectedTabTitle: String? {
        guard tabBar.exists else { return nil }
        guard let selected = tabElements().first(where: { $0.isSelected || "\($0.value ?? "")" == "1" }) else { return nil }
        return selected.title.isEmpty ? selected.label : selected.title
    }

    func closeFrontTab() {
        app.typeKey("w", modifierFlags: .command)
    }

    // MARK: - Reader

    /// Toolbar button that shows or hides the right inspector.
    var inspectorToggle: XCUIElement {
        app.toolbars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'panel'")).firstMatch
    }

    /// True while the right inspector shows its Highlights / Notes picker.
    var isInspectorOpen: Bool {
        app.radioButtons["Notes"].exists && app.radioButtons["Highlights"].exists
    }

    var highlightColorMenu: XCUIElement { app.toolbars.menuButtons["Highlight color"] }

    // MARK: - Menus

    /// Clicks a menu bar item, hovers intermediate submenus, clicks the last title.
    func menu(_ path: String...) {
        var item = app.menuBars.menuBarItems[path[0]]
        item.click()
        for (index, title) in path.dropFirst().enumerated() {
            item = item.menuItems[title]
            if index == path.count - 2 {
                item.click()
            } else {
                item.hover()
            }
        }
    }

    /// Opens the menu, reads whether the item exists and is enabled, closes the menu.
    func menuItemState(_ top: String, _ title: String) -> (exists: Bool, enabled: Bool) {
        let barItem = app.menuBars.menuBarItems[top]
        barItem.click()
        let item = barItem.menuItems[title]
        let state = (item.exists, item.exists && item.isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        return state
    }

    /// Titles of the items directly in a menu bar menu.
    func menuTitles(_ top: String) -> [String] {
        let barItem = app.menuBars.menuBarItems[top]
        barItem.click()
        let titles = barItem.menus.firstMatch.children(matching: .menuItem).allElementsBoundByIndex.map(\.title)
        app.typeKey(.escape, modifierFlags: [])
        return titles
    }

    // MARK: - Categories

    /// Toolbar "+" on the Categories screen. The button's label is "New Category…" (the Label text wins over the
    /// explicit accessibility label in the toolbar).
    /// A category row is one combined static text: "<name>, <kind>, N documents".
    func categoryRow(_ name: String) -> XCUIElement {
        let prefix = name + ","
        return app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", prefix, prefix)).firstMatch
    }

    var newCategoryButton: XCUIElement {
        app.toolbars.buttons.matching(NSPredicate(format: "label BEGINSWITH 'New Category'")).firstMatch
    }

    // MARK: - Sheets and alerts

    var sheet: XCUIElement { app.sheets.firstMatch }

    /// Dismisses the import summary alert if it's showing. Since T52j it appears only when an import needs attention
    /// (duplicates, skipped or failed files). Scoped to the alert's sheet or dialog: an unscoped
    /// `app.buttons["OK"]` can resolve to a Touch Bar element, which can't be clicked.
    func dismissImportAlertIfShown(timeout: TimeInterval = 5) {
        let ok = alertButton("OK")
        if ok.waitForExistence(timeout: timeout) {
            ok.click()
        }
    }

    /// A button in an alert, confirmation dialog or sheet (not the Touch Bar).
    func alertButton(_ title: String) -> XCUIElement {
        let inSheet = app.sheets.buttons[title]
        let inDialog = app.dialogs.buttons[title]
        let inAlert = app.windows.buttons.matching(NSPredicate(format: "title == %@ OR label == %@", title, title)).firstMatch
        if inSheet.exists { return inSheet.firstMatch }
        if inDialog.exists { return inDialog.firstMatch }
        return inAlert
    }

    /// Confirms a destructive confirmation dialog with its "Delete" button.
    func confirmDelete() {
        alertButton("Delete").click()
    }

    /// Selects all text in `field` and types `text` instead.
    func replaceText(in field: XCUIElement, with text: String) {
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
    }

    // MARK: - Evidence

    /// Attaches a screenshot of the whole main display, so menus and sheets are included.
    func attachScreenshot(_ name: String, to testCase: XCTestCase?) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        if let testCase {
            testCase.add(attachment)
        } else {
            XCTContext.runActivity(named: name) { activity in activity.add(attachment) }
        }
    }

    /// Attaches the accessibility hierarchy as text, for diagnosing selector problems.
    func attachHierarchy(_ name: String, to testCase: XCTestCase) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }

    // MARK: - Processes and LaunchServices

    static var runningInstanceCount: Int {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).count
    }

    /// The StudyReader.app built next to this test runner (build/DerivedData/Build/Products/Debug/).
    static var builtAppURL: URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appending(path: "StudyReader.app", directoryHint: .isDirectory)
    }

    /// Opens `urls` with the built app, the way Finder's Open With does.
    static func openExternally(_ urls: [URL], configuration: NSWorkspace.OpenConfiguration) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(urls, withApplicationAt: builtAppURL, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
