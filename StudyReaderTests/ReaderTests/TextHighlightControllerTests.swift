import AppKit
import Foundation
import Testing
@testable import StudyReader

@MainActor
@Suite("TextHighlightController")
struct TextHighlightControllerTests {
    private static let documentId = "30000000-0000-0000-0000-0000000000FA"
    private static let viewSize = CGSize(width: 900, height: 700)
    private static let line = "a bold and italic word with code"
    private static let richLine = "a **bold** and *italic* word with `code`"

    /// Everything one test needs. The window is borderless and never shown; it gives the views a size and a window
    /// so layout runs.
    private struct Harness {
        let session: AppSession
        let model: ReaderModel
        let textController: TextReaderController
        let controller: TextHighlightController
        let window: NSWindow
        let rendered: RenderedMarkdown
    }

    private static func makeHarness(fixture: String = "rich-inline", loadText: Bool = true) async throws -> Harness {
        let session = try ReaderTestSupport.makeSession()
        let environment = session.environment
        try await environment.documentRepository.insert(TestData.document(id: documentId, fileType: .markdown))
        _ = try environment.fileStore.createDocumentFolder(documentId: documentId)
        let url = try environment.fileStore.originalFileURL(documentId: documentId, fileType: .markdown)
        let markdown = try MarkdownFixtures.string(fixture)
        try Data(markdown.utf8).write(to: url)

        let model = ReaderModel(documentId: documentId, session: session)
        await model.load()
        let rendered = MarkdownRenderer.render(MarkdownDocumentSource(
            markdown: markdown,
            documentId: documentId,
            fileStore: environment.fileStore
        ))
        let textController = TextReaderController(model: model)
        let controller = TextHighlightController(model: model, textController: textController)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: viewSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = textController.scrollView
        textController.scrollView.frame = CGRect(origin: .zero, size: viewSize)
        if loadText {
            textController.load(rendered.attributedString)
            controller.setRendered(string: rendered.string, sourceMap: rendered.sourceMap)
        }
        window.layoutIfNeeded()
        return Harness(
            session: session, model: model, textController: textController, controller: controller,
            window: window, rendered: rendered
        )
    }

    private static func range(of text: String, in string: String) throws -> NSRange {
        let range = (string as NSString).range(of: text)
        try #require(range.location != NSNotFound)
        return range
    }

    private static func highlight(
        id: String,
        range: NSRange,
        in string: String,
        status: AnchorStatus = .ok,
        color: HighlightColor = .yellow,
        createdAt: Date = TestData.referenceDate
    ) -> Highlight {
        let anchor = TextAnchoring.anchor(for: range, in: string, sourceVersion: MarkdownRenderer.version)
        return Highlight(
            id: id, documentId: documentId, kind: .text, view: .markdown, color: color,
            text: anchor.text, richText: anchor.text, positionKey: TextAnchoring.positionKey(for: anchor),
            anchor: .text(anchor), anchorStatus: status, createdAt: createdAt, updatedAt: createdAt)
    }

    /// UTF-16 offsets the text view paints a highlight over.
    private static func coloredOffsets(_ textController: TextReaderController) -> IndexSet {
        var offsets = IndexSet()
        for paint in textController.textView.highlightPaints {
            offsets.insert(integersIn: paint.range.location..<NSMaxRange(paint.range))
        }
        return offsets
    }

    private static func finish(_ harness: Harness) async throws {
        try await harness.session.environment.database.writer.write { db in try FTSIntegrity.check(db) }
    }

    // MARK: - Tests

    @Test(.timeLimit(.minutes(1)))
    func newHighlightStoresRichText() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let string = harness.rendered.string
        let range = try Self.range(of: Self.line, in: string)

        let new = try #require(harness.controller.newHighlight(for: range, color: .blue))

        #expect(new.richText == Self.richLine)
        #expect(new.view == .markdown)
        #expect(new.text == Self.line)
        #expect(new.color == .blue)
        #expect(new.pageIndex == nil)
        #expect(new.positionKey == 0)
        guard case .text(let anchor) = new.anchor else {
            Issue.record("expected a text anchor")
            return
        }
        #expect(anchor.sourceVersion == MarkdownRenderer.version)
        #expect(anchor.start == range.location)
        #expect(anchor.length == range.length)

        let created = try #require(await harness.model.createHighlight(new, isAuto: false))
        #expect(created.richText == Self.richLine)
        try await Self.finish(harness)
    }

    @Test(.timeLimit(.minutes(1)))
    func newHighlightRejectsWhitespaceAndOutOfRange() async throws {
        let harness = try await Self.makeHarness(fixture: "all-elements")
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let string = harness.rendered.string as NSString
        let space = string.range(of: " ")
        try #require(space.location != NSNotFound)

        #expect(harness.controller.newHighlight(for: NSRange(location: space.location, length: 1), color: .yellow) == nil)
        #expect(harness.controller.newHighlight(for: NSRange(location: 0, length: 0), color: .yellow) == nil)
        #expect(harness.controller.newHighlight(for: NSRange(location: string.length - 1, length: 5), color: .yellow) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func reanchorMovesAndOrphans() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let string = harness.rendered.string
        let repository = harness.session.environment.highlightRepository
        let real = try Self.range(of: "italic word", in: string)

        var shifted = Self.highlight(id: "moved", range: real, in: string)
        guard case .text(var shiftedAnchor) = shifted.anchor else { return }
        shiftedAnchor.start += 7
        shiftedAnchor.sourceVersion = 0
        shifted.anchor = .text(shiftedAnchor)
        shifted.positionKey = Double(shiftedAnchor.start)
        try await repository.insert(shifted)

        #expect(await harness.controller.reanchorAll([shifted]) == 1)
        let movedRow = try #require(try await repository.fetch(id: "moved"))
        guard case .text(let movedAnchor) = movedRow.anchor else {
            Issue.record("expected a text anchor")
            return
        }
        #expect(movedAnchor.start == real.location)
        #expect(movedAnchor.length == real.length)
        #expect(movedAnchor.sourceVersion == MarkdownRenderer.version)
        #expect(movedRow.anchorStatus == .ok)
        #expect(movedRow.positionKey == Double(real.location))

        var lost = Self.highlight(id: "lost", range: real, in: string)
        guard case .text(var lostAnchor) = lost.anchor else { return }
        lostAnchor.text = "text that is nowhere in the document"
        lostAnchor.length = lostAnchor.text.utf16.count
        lost.anchor = .text(lostAnchor)
        try await repository.insert(lost)

        #expect(await harness.controller.reanchorAll([lost]) == 1)
        let lostRow = try #require(try await repository.fetch(id: "lost"))
        #expect(lostRow.anchorStatus == .orphaned)
        #expect(lostRow.anchor == lost.anchor)
        #expect(lostRow.positionKey == lost.positionKey)

        let all = try await repository.fetchForDocument(Self.documentId)
        #expect(all.count == 2)
        #expect(await harness.controller.reanchorAll(all) == 0)
        try await Self.finish(harness)
    }

    @Test(.timeLimit(.minutes(1)))
    func orphanThatResolvesIsRestored() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let string = harness.rendered.string
        let repository = harness.session.environment.highlightRepository
        let orphan = Self.highlight(
            id: "back", range: try Self.range(of: "bold", in: string), in: string, status: .orphaned)
        try await repository.insert(orphan)

        #expect(await harness.controller.reanchorAll([orphan]) == 1)

        let row = try #require(try await repository.fetch(id: "back"))
        #expect(row.anchorStatus == .ok)
        #expect(await harness.controller.reanchorAll([row]) == 0)
        try await Self.finish(harness)
    }

    @Test(.timeLimit(.minutes(1)))
    func hitTestNewestFirst() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let string = harness.rendered.string
        let wide = try Self.range(of: "bold and italic", in: string)
        let narrow = try Self.range(of: "and italic word", in: string)
        let older = Self.highlight(id: "older", range: wide, in: string)
        let newer = Self.highlight(
            id: "newer", range: narrow, in: string, createdAt: TestData.referenceDate.addingTimeInterval(5))

        harness.controller.sync(with: [newer, older])

        let shared = narrow.location + 1
        #expect(harness.controller.highlightIds(atCharacterIndex: shared) == ["newer", "older"])
        #expect(harness.controller.highlightIds(atCharacterIndex: wide.location) == ["older"])
        #expect(harness.controller.highlightIds(atCharacterIndex: NSMaxRange(narrow)) == [])
    }

    @Test(.timeLimit(.minutes(1)))
    func syncSkipsOrphans() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let string = harness.rendered.string
        let okRange = try Self.range(of: "bold", in: string)
        let orphanRange = try Self.range(of: "code", in: string)
        let ok = Self.highlight(id: "ok", range: okRange, in: string, color: .green)
        let orphan = Self.highlight(id: "orphan", range: orphanRange, in: string, status: .orphaned)

        harness.controller.sync(with: [ok, orphan])

        #expect(Self.coloredOffsets(harness.textController) == IndexSet(integersIn: okRange.location..<NSMaxRange(okRange)))
        #expect(harness.controller.highlightIds(atCharacterIndex: orphanRange.location) == [])

        harness.controller.sync(with: [])
        #expect(Self.coloredOffsets(harness.textController).isEmpty)
        #expect(harness.controller.highlightIds(atCharacterIndex: okRange.location) == [])
    }

    @Test(.timeLimit(.minutes(1)))
    func revealSelectsRange() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let string = harness.rendered.string
        let range = try Self.range(of: "italic word", in: string)
        let stored = Self.highlight(id: "target", range: range, in: string)
        try await harness.session.environment.highlightRepository.insert(stored)
        let observer = Task { await harness.model.observeHighlights() }
        defer { observer.cancel() }
        let loaded = await ReaderTestSupport.waitUntil { harness.model.highlights.count == 1 }
        try #require(loaded)

        #expect(harness.controller.reveal(highlightId: "missing") == false)
        #expect(harness.controller.reveal(highlightId: "target"))

        #expect(harness.textController.textView.selectedRange() == range)
        // Nothing was synced before: reveal draws first, so the highlight is drawn and hit-testable.
        #expect(harness.controller.highlightIds(atCharacterIndex: range.location) == ["target"])
        #expect(!Self.coloredOffsets(harness.textController).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func revealOfOrphanDoesNothing() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let string = harness.rendered.string
        let orphan = Self.highlight(
            id: "orphan", range: try Self.range(of: "bold", in: string), in: string, status: .orphaned)
        try await harness.session.environment.highlightRepository.insert(orphan)
        let observer = Task { await harness.model.observeHighlights() }
        defer { observer.cancel() }
        let loaded = await ReaderTestSupport.waitUntil { harness.model.highlights.count == 1 }
        try #require(loaded)

        #expect(harness.controller.reveal(highlightId: "orphan"))

        #expect(harness.textController.textView.selectedRange().length == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func autoHighlightCreatesCollapsesAndUndoes() async throws {
        let harness = try await Self.makeHarness()
        defer { ReaderTestSupport.cleanUp(harness.session) }
        harness.session.settings.autoHighlight = true
        harness.session.settings.currentColor = .pink
        let observer = Task { await harness.model.observeHighlights() }
        defer { observer.cancel() }
        let range = try Self.range(of: "italic word", in: harness.rendered.string)
        let textView = harness.textController.textView
        textView.setSelectedRange(range)

        textView.onSelectionFinished?(range)

        let created = await ReaderTestSupport.waitUntil { harness.model.highlights.count == 1 }
        #expect(created)
        #expect(harness.model.highlights.first?.color == .pink)
        let collapsed = await ReaderTestSupport.waitUntil { textView.selectedRange().length == 0 }
        #expect(collapsed)
        let undoManager = try #require(textView.undoManager ?? harness.window.undoManager)
        let canUndo = await ReaderTestSupport.waitUntil { undoManager.canUndo }
        try #require(canUndo)
        #expect(undoManager.undoActionName == String(localized: "Highlight"))

        undoManager.undo()

        let removed = await ReaderTestSupport.waitUntil { harness.model.highlights.isEmpty }
        #expect(removed)
        try await Self.finish(harness)
    }

    @Test(.timeLimit(.minutes(1)))
    func coordinatorRevealsPendingHighlightAfterReanchoring() async throws {
        let harness = try await Self.makeHarness(loadText: false)
        defer { ReaderTestSupport.cleanUp(harness.session) }
        let string = harness.rendered.string
        let range = try Self.range(of: "italic word", in: string)
        // Stored with an old renderer version and a wrong start: the coordinator has to re-anchor before it reveals.
        var stale = Self.highlight(id: "target", range: range, in: string)
        guard case .text(var staleAnchor) = stale.anchor else { return }
        staleAnchor.start += 5
        staleAnchor.sourceVersion = 0
        stale.anchor = .text(staleAnchor)
        let repository = harness.session.environment.highlightRepository
        try await repository.insert(stale)
        let observer = Task { await harness.model.observeHighlights() }
        defer { observer.cancel() }
        let loaded = await ReaderTestSupport.waitUntil { harness.model.highlights.count == 1 }
        try #require(loaded)
        let coordinator = MarkdownReaderCoordinator(model: harness.model)
        harness.window.contentView = coordinator.controller.scrollView
        coordinator.controller.scrollView.frame = CGRect(origin: .zero, size: Self.viewSize)
        harness.model.navigate(to: .highlight("target"))

        coordinator.loadIfNeeded()

        let consumed = await ReaderTestSupport.waitUntil(timeout: .seconds(10)) {
            harness.model.pendingLocation == nil
        }
        #expect(consumed)
        #expect(coordinator.controller.textView.selectedRange() == range)
        let row = try #require(try await repository.fetch(id: "target"))
        guard case .text(let anchor) = row.anchor else {
            Issue.record("expected a text anchor")
            return
        }
        #expect(anchor.start == range.location)
        #expect(anchor.sourceVersion == MarkdownRenderer.version)
        try await Self.finish(harness)
    }
}
