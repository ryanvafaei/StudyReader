import AppKit
import SwiftUI

/// The Markdown reader of one tab (SPEC F-03): the stored file rendered by `MarkdownRenderer` into the shared
/// `TextReaderView`, with highlights drawn, created and re-anchored by `TextHighlightController` (T60). The
/// coordinator is created on first appearance, so a re-evaluated parent doesn't build a second text view.
struct MarkdownReaderView: View {
    let model: ReaderModel
    @State private var coordinator: MarkdownReaderCoordinator?

    var body: some View {
        Group {
            if let coordinator {
                MarkdownReaderContent(coordinator: coordinator, model: model)
            } else {
                Color.clear
            }
        }
        .task {
            if coordinator == nil {
                coordinator = MarkdownReaderCoordinator(model: model)
            }
        }
    }
}

private struct MarkdownReaderContent: View {
    let coordinator: MarkdownReaderCoordinator
    let model: ReaderModel

    var body: some View {
        MarkdownTextHost(coordinator: coordinator)
            .task {
                // Loading may change the model (a failed read), which must not happen during a view update.
                coordinator.loadIfNeeded()
            }
            .task(id: model.pendingLocation) {
                coordinator.applyPendingLocation()
            }
            .onChange(of: model.highlights) {
                coordinator.highlightsChanged()
            }
            .onDisappear {
                coordinator.tearDown()
            }
    }
}

/// Puts the controller's scroll view into SwiftUI.
private struct MarkdownTextHost: NSViewRepresentable {
    let coordinator: MarkdownReaderCoordinator

    func makeNSView(context: Context) -> NSScrollView {
        coordinator.controller.scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

@MainActor
final class MarkdownReaderCoordinator {
    let model: ReaderModel
    let controller: TextReaderController
    let highlightController: TextHighlightController
    /// The last rendering; nil until the file has been read.
    private(set) var rendered: RenderedMarkdown?
    private static let freshnessChecks = 100
    private static let freshnessInterval: Duration = .milliseconds(20)
    private var didAttemptLoad = false
    private var didReanchor = false
    private var isReanchoring = false

    init(model: ReaderModel) {
        self.model = model
        self.controller = TextReaderController(model: model)
        self.highlightController = TextHighlightController(model: model, textController: controller)
        controller.onPositionReady = { [weak self] in self?.positionReady() }
    }

    /// The text has a layout and its saved position is restored. Draws the highlights again: a draw made before the
    /// first layout (while the column inset and the view size were still changing) must not be the only one.
    private func positionReady() {
        if rendered != nil, !isReanchoring, didReanchor || model.highlights.isEmpty {
            highlightController.sync(with: model.highlights)
        }
        applyPendingLocation()
    }

    /// Reads the stored file as UTF-8, renders it and shows it. An unreadable file fails the model.
    func loadIfNeeded() {
        guard !didAttemptLoad else { return }
        didAttemptLoad = true
        guard let url = model.fileURL, let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            model.engineFailed(String(localized: "Couldn't read this document."))
            return
        }
        let source = MarkdownDocumentSource(
            markdown: markdown,
            documentId: model.documentId,
            fileStore: model.session.environment.fileStore
        )
        let result = MarkdownRenderer.render(source)
        rendered = result
        highlightController.setRendered(string: result.string, sourceMap: result.sourceMap)
        controller.load(result.attributedString)
        highlightsChanged()
    }

    /// `model.highlights` changed (or the text was just shown). The first time there are highlights they are
    /// re-anchored against the rendering, then drawn. Later changes are drawn at once.
    func highlightsChanged() {
        guard rendered != nil, !isReanchoring else { return }
        if !didReanchor, !model.highlights.isEmpty {
            didReanchor = true
            isReanchoring = true
            let snapshot = model.highlights
            Task { @MainActor [weak self] in
                guard let self else { return }
                if await highlightController.reanchorAll(snapshot) > 0 {
                    await waitForReanchoredRows()
                }
                isReanchoring = false
                highlightsChanged()
            }
            return
        }
        highlightController.sync(with: model.highlights)
        applyPendingLocation()
    }

    /// Re-anchoring wrote new anchors; `model.highlights` follows through the database observation a moment later.
    /// Waits (bounded) until it shows the stored rows, so nothing is drawn or revealed at an outdated position.
    private func waitForReanchoredRows() async {
        let environment = model.session.environment
        guard let stored = try? await environment.highlightRepository.fetchForDocument(model.documentId) else { return }
        for _ in 0..<Self.freshnessChecks {
            if model.highlights == stored { return }
            try? await environment.sleeper.sleep(for: Self.freshnessInterval)
            await Task.yield()
        }
    }

    /// Applies a `.highlight` or `.searchHit` location the model holds and consumes it. Waits for the saved reading
    /// position to be restored (`onPositionReady` retries) and for the re-anchoring, and stays pending while the
    /// highlight isn't loaded yet; `highlightsChanged()` retries it. `reveal` draws before it selects. A search hit
    /// selects the first match of the query's first positive term in the section (the start of the document for a
    /// section that doesn't exist) and just scrolls to the section when the query has no such term or it isn't found.
    func applyPendingLocation() {
        guard rendered != nil, controller.isTrackingPosition, !isReanchoring else { return }
        if !didReanchor, !model.highlights.isEmpty {
            highlightsChanged()
            return
        }
        switch model.pendingLocation {
        case .highlight(let id):
            guard highlightController.reveal(highlightId: id) else { return }
        case .searchHit(let unitIndex, let query):
            showSearchHit(unitIndex: unitIndex, query: query)
        default:
            return
        }
        model.consumeLocation()
    }

    private func showSearchHit(unitIndex: Int, query: String) {
        guard let rendered else { return }
        let text = rendered.string as NSString
        let section = rendered.sections.indices.contains(unitIndex)
            ? rendered.sections[unitIndex]
            : NSRange(location: 0, length: text.length)
        // A match outside the section (the search index and this match differ in what they equate) isn't shown.
        if let term = SearchQueryParser.firstPositiveTerm(in: query),
           let match = PlainTextFinder.firstRange(of: term, in: text, from: section.location),
           NSLocationInRange(match.location, section),
           controller.selectFirstMatch(of: term, from: section.location) {
            controller.textView.window?.makeFirstResponder(controller.textView)
        } else {
            controller.scroll(toOffset: section.location)
        }
    }

    /// The tab is going away: drop the undo action for the last auto-highlight.
    func tearDown() {
        highlightController.tearDown()
    }
}
