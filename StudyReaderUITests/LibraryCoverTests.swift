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
}
