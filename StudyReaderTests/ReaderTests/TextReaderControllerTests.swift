import AppKit
import Foundation
import Testing
@testable import StudyReader

@MainActor
@Suite("TextReaderController")
struct TextReaderControllerTests {
    private static let documentId = "30000000-0000-0000-0000-0000000000F7"
    private static let viewSize = CGSize(width: 900, height: 700)
    private static let targetLine = "Final paragraph after the images."

    /// Everything one test needs. The window is borderless and never shown; it gives the views a size and a window
    /// so layout runs.
    private struct Harness {
        let session: AppSession
        let model: ReaderModel
        let controller: TextReaderController
        let window: NSWindow
        let rendered: RenderedMarkdown
        /// The rendered document three times in a row, so the first copy's last line can scroll to the top.
        let tripled: NSAttributedString
    }

    private static func makeHarness(savedOffset: Int? = nil) async throws -> Harness {
        let session = try ReaderTestSupport.makeSession()
        let environment = session.environment
        try await environment.documentRepository.insert(TestData.document(id: documentId, fileType: .markdown))
        _ = try environment.fileStore.createDocumentFolder(documentId: documentId)
        let url = try environment.fileStore.originalFileURL(documentId: documentId, fileType: .markdown)
        let markdown = try MarkdownFixtures.string("all-elements")
        try Data(markdown.utf8).write(to: url)
        if let savedOffset {
            try await environment.documentRepository.updateTextPosition(id: documentId, offset: savedOffset, progress: 0.5)
        }

        let model = ReaderModel(documentId: documentId, session: session)
        await model.load()
        let rendered = MarkdownRenderer.render(MarkdownDocumentSource(
            markdown: markdown,
            documentId: documentId,
            fileStore: environment.fileStore
        ))
        let tripled = NSMutableAttributedString()
        for copy in 0..<3 {
            if copy > 0 { tripled.append(NSAttributedString(string: "\n")) }
            tripled.append(rendered.attributedString)
        }
        let controller = TextReaderController(model: model)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: viewSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = controller.scrollView
        controller.scrollView.frame = CGRect(origin: .zero, size: viewSize)
        window.layoutIfNeeded()
        return Harness(session: session, model: model, controller: controller, window: window, rendered: rendered, tripled: tripled)
    }

    /// Suspends the test so the main queue runs (the controller's layout wait). Spinning the run loop inside the test
    /// doesn't work: the test itself runs in a main-queue block.
    private static func settle(_ seconds: Double = 0.3) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    private static func offset(of text: String, in string: String) throws -> Int {
        let range = (string as NSString).range(of: text)
        try #require(range.location != NSNotFound)
        return range.location
    }

    @Test(.timeLimit(.minutes(1)))
    func loadsRenderedText() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }

        harness.controller.load(harness.rendered.attributedString)

        #expect(harness.controller.textLength == harness.rendered.string.utf16.count)
        #expect(harness.controller.textView.string == harness.rendered.string)
        #expect(harness.controller.textView.isEditable == false)
        #expect(harness.controller.textView.isSelectable)
        #expect(harness.controller.textView.textLayoutManager != nil)
        #expect(harness.model.engineActions.findInDocument != nil)
        #expect(harness.model.engineActions.copySelection != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func scrollRoundTrip() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        harness.controller.load(harness.tripled)
        try await Self.settle()

        let target = try Self.offset(of: Self.targetLine, in: harness.tripled.string)
        harness.controller.scroll(toOffset: target)
        try await Self.settle(0.2)

        let first = try #require(harness.controller.firstVisibleOffset())
        #expect(abs(first - target) <= Self.targetLine.utf16.count)
        #expect(harness.controller.scrollView.contentView.bounds.minY > 0)
    }

    /// The nil case (text but no layout fragment) has no reliable setup: TextKit 2 lays out on demand, also for a
    /// zero-width container and for a visible area far below the last line, so a fragment is always found.
    @Test(.timeLimit(.minutes(1)))
    func firstVisibleOffsetIsZeroForEmptyTextAndFoundWithLayout() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }

        harness.controller.load(NSAttributedString())
        #expect(harness.controller.firstVisibleOffset() == 0)

        harness.controller.load(harness.rendered.attributedString)
        try await Self.settle()
        #expect(harness.controller.textLength > 0)
        #expect(harness.controller.firstVisibleOffset() != nil)
    }

    @Test func paintsToDrawClipsToViewport() {
        let color = NSColor.yellow
        let paints = [
            TextReaderView.HighlightPaint(range: NSRange(location: 0, length: 10), color: color),
            TextReaderView.HighlightPaint(range: NSRange(location: 50, length: 10), color: color),
            TextReaderView.HighlightPaint(range: NSRange(location: 95, length: 25), color: color)
        ]
        let clipped = TextReaderView.paintsToDraw(paints, viewport: NSRange(location: 40, length: 60))
        #expect(clipped.map(\.range) == [NSRange(location: 50, length: 10), NSRange(location: 95, length: 5)])
        #expect(clipped.allSatisfy { $0.color == color })
        #expect(TextReaderView.paintsToDraw(paints, viewport: nil) == paints)
    }

    @Test(.timeLimit(.minutes(1)))
    func restoresInitialOffset() async throws {
        // Image attachments are one character whether or not the file exists, so this offset matches the harness text.
        let plain = MarkdownRenderer.render(MarkdownDocumentSource(
            markdown: try MarkdownFixtures.string("all-elements"),
            documentId: nil,
            fileStore: nil
        ))
        let target = try Self.offset(of: Self.targetLine, in: plain.string)
        let harness = try await Self.makeHarness(savedOffset: target)
        defer { ReaderTestSupport.cleanUp(harness.session) }
        #expect(harness.model.initialTextOffset == target)

        harness.controller.load(harness.tripled)
        try await Self.settle(0.8)

        let rendered = try Self.offset(of: Self.targetLine, in: harness.tripled.string)
        let first = try #require(harness.controller.firstVisibleOffset())
        #expect(abs(first - rendered) <= Self.targetLine.utf16.count, "first visible \(first), target \(rendered)")
    }

    @Test(.timeLimit(.minutes(1)))
    func scrollingSavesThePositionAfterTheInitialRestore() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        harness.controller.load(harness.tripled)
        try await Self.settle()

        let target = try Self.offset(of: Self.targetLine, in: harness.tripled.string)
        harness.controller.scroll(toOffset: target)
        try await Self.settle(0.2)
        await harness.model.flushPosition()

        let row = await ReaderTestSupport.row(harness.session, id: Self.documentId)
        let saved = try #require(row?.textPosition)
        #expect(abs(saved - target) <= Self.targetLine.utf16.count)
    }

    @Test(.timeLimit(.minutes(1)))
    func anchorRectIsInsideView() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        harness.controller.load(harness.rendered.attributedString)
        try await Self.settle()

        let start = try Self.offset(of: "Heading 2", in: harness.rendered.string)
        let rect = harness.controller.anchorRect(for: NSRange(location: start, length: 9))

        #expect(rect.width > 0)
        #expect(rect.height > 0)
        #expect(harness.controller.scrollView.bounds.contains(rect))
    }

    @Test(.timeLimit(.minutes(1)))
    func characterIndexFindsTheCharacterUnderThePoint() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        harness.controller.load(harness.rendered.attributedString)
        try await Self.settle()

        let range = NSRange(location: try Self.offset(of: "Ordered item one", in: harness.rendered.string), length: 16)
        let rect = harness.controller.anchorRect(for: range)
        let scrollView = harness.controller.scrollView
        // anchorRect is top-left origin; AppKit conversion needs the view's own coordinates.
        let inScrollView = CGPoint(x: rect.midX, y: scrollView.isFlipped ? rect.midY : scrollView.bounds.height - rect.midY)
        let point = scrollView.convert(inScrollView, to: harness.controller.textView)

        let index = try #require(harness.controller.textView.characterIndex(at: point))
        #expect(NSLocationInRange(index, range))
    }

    @Test(.timeLimit(.minutes(1)))
    func insetCentersColumn() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        harness.controller.load(harness.rendered.attributedString)

        harness.window.setContentSize(CGSize(width: 1200, height: 700))
        harness.window.layoutIfNeeded()

        #expect(harness.controller.scrollView.bounds.width == 1200)
        #expect(harness.controller.textView.textContainerInset.width == 240)
        #expect(harness.controller.textView.textContainerInset.height == TextReaderController.verticalInset)
    }

    @Test
    func columnInsetMath() {
        #expect(TextReaderController.columnInset(forViewWidth: 1200) == 240)
        #expect(TextReaderController.columnInset(forViewWidth: 720) == 24)
        #expect(TextReaderController.columnInset(forViewWidth: 400) == 24)
    }

    @Test(.timeLimit(.minutes(1)))
    func unreadableFileFailsTheModel() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let url = try #require(harness.model.fileURL)
        try Data([0xFF, 0xFE, 0xFD]).write(to: url)
        let coordinator = MarkdownReaderCoordinator(model: harness.model)

        coordinator.loadIfNeeded()

        #expect(harness.model.state == .failed(String(localized: "Couldn't read this document.")))
        #expect(!harness.model.isDocumentAvailable)
        #expect(coordinator.rendered == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func readableFileIsRenderedAndKept() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let coordinator = MarkdownReaderCoordinator(model: harness.model)

        coordinator.loadIfNeeded()

        #expect(coordinator.rendered?.string == harness.rendered.string)
        #expect(coordinator.controller.textLength == harness.rendered.string.utf16.count)
        #expect(harness.model.isDocumentAvailable)
    }

    @Test
    func onlyWebAndMailLinksOpen() throws {
        for allowed in ["https://www.apple.com", "http://example.com/a", "mailto:a@example.com", "HTTPS://example.com"] {
            #expect(LinkPolicy.isOpenable(try #require(URL(string: allowed))), "\(allowed)")
        }
        for blocked in ["file:///etc/passwd", "javascript:alert(1)", "ftp://example.com", "x-apple.systempreferences:", "images/a.png"] {
            #expect(!LinkPolicy.isOpenable(try #require(URL(string: blocked))), "\(blocked)")
        }
        #expect(TextReaderView.url(forLink: "https://www.apple.com") == URL(string: "https://www.apple.com"))
        #expect(TextReaderView.url(forLink: 42) == nil)
    }

    @Test
    func blockAttributesChooseTheDecoration() {
        let plain: [NSAttributedString.Key: Any] = [:]
        let code: [NSAttributedString.Key: Any] = [.studyCodeBlock: true]
        let quoteStyle = NSMutableParagraphStyle()
        quoteStyle.firstLineHeadIndent = 16
        let quote: [NSAttributedString.Key: Any] = [.studyBlockQuote: true, .paragraphStyle: quoteStyle]
        let rule: [NSAttributedString.Key: Any] = [.studyHorizontalRule: true]

        #expect(TextBlockDecoration.decoration(for: plain, previous: nil, next: nil) == nil)
        #expect(TextBlockDecoration.decoration(for: code, previous: plain, next: code) == .codeBlock(continuesAbove: false, continuesBelow: true))
        #expect(TextBlockDecoration.decoration(for: code, previous: code, next: nil) == .codeBlock(continuesAbove: true, continuesBelow: false))
        #expect(TextBlockDecoration.decoration(for: quote, previous: nil, next: nil) == .blockQuote(indent: 16))
        #expect(TextBlockDecoration.decoration(for: rule, previous: nil, next: nil) == .horizontalRule)
        #expect(TextBlockDecoration.quoteBarOffset(indent: 16, linePadding: 5) == 9)
        #expect(TextBlockDecoration.quoteBarOffset(indent: 0, linePadding: 5) == 5)
    }
}
