import AppKit
import XCTest

private typealias Sample = StudyReaderUI.Sample

/// T52 checkpoint steps 8 and 9 (T48 covers): one frame for every card, landscape covers aspect-fit over a blurred
/// background, and the selection fill. Pixel checks are heuristics; the attached crops are for the ui-tester's review.
final class LibraryCoverTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// Step 8: every card shares one frame.
    @MainActor
    func testAllCardsShareOneWidth() {
        let ui = StudyReaderUI.launch()
        ui.enlargeWindow()
        let titles = [Sample.lecture, Sample.sparse, Sample.gradient, Sample.retrieval, Sample.pendulum, Sample.membrane]
        let frames = titles.map { ui.cardFrame(of: $0) }
        let widths = frames.map(\.width)
        XCTAssertLessThanOrEqual((widths.max() ?? 0) - (widths.min() ?? 0), 1, "Card widths differ: \(frames)")
    }

    /// Step 8: the 16:9 "Slides: Membrane Transport" cover is aspect-fit in the middle of the 3:4 frame, with a
    /// blurred copy above and below. So the top fifth of the frame has no sharp content. At the T52 checkpoint the
    /// slide filled the frame (cropped left and right) and its text sat sharp at the top.
    @MainActor
    func testLandscapeCoverIsFittedOverABlurredBackground() {
        let ui = StudyReaderUI.launch()
        ui.enlargeWindow()
        XCTAssertTrue(ui.card(Sample.membrane).waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let cover = ui.coverRect(of: Sample.membrane)
        ScreenPixels.attach(cover, named: "Step 8 landscape cover", to: self)

        let topBand = CGRect(x: cover.minX + 6, y: cover.minY + 6, width: cover.width - 12, height: cover.height * 0.2)
        let stats = ScreenPixels.stats(of: topBand)
        XCTAssertNotNil(stats, "No pixels for \(topBand); card frame \(ui.card(Sample.membrane).frame), cover \(cover), screens \(NSScreen.screens.map(\.frame))")
        XCTAssertLessThan(
            stats?.luminanceRange ?? 1,
            0.35,
            "The top of the cover has sharp content: the slide fills the frame instead of being aspect-fit (DocumentCoverView)."
        )
    }

    /// Step 9: only the selected card has the light-blue fill. Visual check: the crops go to the ui-tester.
    @MainActor
    func testSelectionFillCrops() {
        let ui = StudyReaderUI.launch()
        ui.enlargeWindow()
        ui.card(Sample.lecture).click()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let selected = ui.coverRect(of: Sample.lecture).insetBy(dx: -12, dy: -12)
        let unselected = ui.coverRect(of: Sample.gradient).insetBy(dx: -12, dy: -12)
        ScreenPixels.attach(selected.union(ui.card(Sample.lecture).frame.insetBy(dx: -12, dy: -12)), named: "Step 9 selected card", to: self)
        ScreenPixels.attach(unselected.union(ui.card(Sample.gradient).frame.insetBy(dx: -12, dy: -12)), named: "Step 9 unselected Markdown card", to: self)
    }

    /// U4, S2: a placeholder cover has a neutral tint (the accent colour is reserved for the selection), and the
    /// selection fill is clearly different. Heuristic in light appearance; the crops are for the ui-tester.
    @MainActor
    func testPlaceholderCoversAreNeutralAndTheSelectionStandsOut() {
        let ui = StudyReaderUI.launch()
        ui.enlargeWindow()
        XCTAssertTrue(ui.card(Sample.gradient).waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        let cover = ui.coverRect(of: Sample.gradient)
        let cardFrame = ui.cardFrame(of: Sample.gradient)
        let inset = cover.insetBy(dx: 6, dy: 6)
        // The top fifth of the cover, above the document symbol.
        let topFifth = CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: inset.height * 0.2)
        // A strip in the card's left padding, outside the cover: only the selection fill reaches it.
        let paddingStrip = CGRect(x: cardFrame.minX + 1, y: cover.midY - 20, width: 5, height: 40)

        let unselectedCover = ScreenPixels.stats(of: topFifth)
        XCTAssertNotNil(unselectedCover, "No pixels for \(topFifth); cover \(cover).")
        XCTAssertLessThan(
            (unselectedCover?.blue ?? 1) - (unselectedCover?.red ?? 0), 0.05,
            "The unselected placeholder cover has an accent tint (DocumentCoverView.GeneratedCoverView)."
        )
        let unselectedPadding = ScreenPixels.stats(of: paddingStrip)
        XCTAssertLessThan(
            (unselectedPadding?.blue ?? 1) - (unselectedPadding?.red ?? 0), 0.05,
            "The unselected card has a blue background."
        )
        ScreenPixels.attach(cardFrame.insetBy(dx: -12, dy: -12), named: "Placeholder unselected", to: self)

        ui.card(Sample.gradient).click()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let selectedPadding = ScreenPixels.stats(of: paddingStrip)
        XCTAssertNotNil(selectedPadding, "No pixels for \(paddingStrip).")
        XCTAssertGreaterThan(
            (selectedPadding?.blue ?? 0) - (selectedPadding?.red ?? 1), 0.1,
            "The selected card has no visible blue fill and border."
        )
        ScreenPixels.attach(cardFrame.insetBy(dx: -12, dy: -12), named: "Placeholder selected", to: self)
    }

    /// S3: a white first-page cover has a visible edge on the white window background (the hairline in
    /// DocumentCoverView). Without it the edge gives about 0 luminance range.
    @MainActor
    func testWhiteCoverHasAVisibleEdge() {
        let ui = StudyReaderUI.launch()
        ui.enlargeWindow()
        XCTAssertTrue(ui.card(Sample.sparse).waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        let cover = ui.coverRect(of: Sample.sparse)
        let edge = CGRect(x: cover.minX - 3, y: cover.midY - 20, width: 6, height: 40)
        let stats = ScreenPixels.stats(of: edge)
        XCTAssertNotNil(stats, "No pixels for \(edge); cover \(cover).")
        XCTAssertGreaterThan(
            stats?.luminanceRange ?? 0, 0.05,
            "The white cover has no visible edge against the window background (DocumentCoverView hairline)."
        )
        ScreenPixels.attach(cover.insetBy(dx: -12, dy: -12), named: "White cover edge", to: self)
    }

    /// U1: nothing invisible in the library takes focus, so no focus ring (a blue line) shows at the content's left
    /// edge. The strip runs from the sidebar to the cards' left edge, in the lower half of the top-most left-column
    /// card. The top-most card is used, not the lowest: on the CI runner the bottom of the screen is covered by the
    /// Dock, and the lowest card's bottom edge overlapped it (a blue Dock icon in the strip, not a focus ring). A focus
    /// ring along the scroll view's left edge still runs alongside the top card, so the strip catches it.
    /// A card is clicked first, as in the original U1 check: the focus ring appeared after a click. The selection
    /// background spans the card's outer edge (`cardFrame.minX`, which is the text block's minX minus 8 pt padding) to
    /// +2 pt for the border, and the strip ends 6 pt before that edge, so the selected card's border stays out of it.
    @MainActor
    func testNoFocusRingAtTheContentLeftEdge() {
        let ui = StudyReaderUI.launch()
        ui.enlargeWindow()
        ui.card(Sample.lecture).click()
        ui.settle()

        let titles = [Sample.lecture, Sample.sparse, Sample.gradient, Sample.retrieval, Sample.pendulum, Sample.membrane]
        let frames = titles.map { ui.cardFrame(of: $0) }
        let left = frames.map(\.minX).min() ?? 0
        // Among the left-column cards, the top-most one (well above the Dock).
        let topmost = frames.filter { abs($0.minX - left) < 1 }.min { $0.midY < $1.midY } ?? .zero

        let startX = ui.sidebar.frame.maxX + 1
        let strip = CGRect(x: startX, y: topmost.midY, width: left - 6 - startX, height: topmost.maxY - topmost.midY)
        guard strip.width >= 2 else {
            XCTFail("The strip between the sidebar and the content is under 2 pt wide. Sidebar \(ui.sidebar.frame), cards \(frames).")
            return
        }
        ScreenPixels.attach(strip.insetBy(dx: -4, dy: 0), named: "Content left edge", to: self)
        let stats = ScreenPixels.stats(of: strip)
        XCTAssertNotNil(stats, "No pixels for \(strip).")
        XCTAssertLessThan(
            stats?.maxSaturation ?? 1, 0.35,
            "A saturated blue line sits at the content's left edge: a focus ring on an invisible control. Strip \(strip)."
        )
    }
}
