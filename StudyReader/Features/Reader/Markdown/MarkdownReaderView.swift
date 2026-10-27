import AppKit
import SwiftUI

/// The Markdown reader of one tab (SPEC F-03): the stored file rendered by `MarkdownRenderer` into the shared
/// `TextReaderView`. The coordinator keeps the `RenderedMarkdown` for the highlight tasks (T58/T60 need `sourceMap`).
struct MarkdownReaderView: NSViewRepresentable {
    let model: ReaderModel

    func makeCoordinator() -> MarkdownReaderCoordinator {
        MarkdownReaderCoordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        // Loading changes the model (a failed read), which must not happen during a view update.
        Task { @MainActor in
            coordinator.loadIfNeeded()
        }
        return coordinator.controller.scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

@MainActor
final class MarkdownReaderCoordinator {
    let model: ReaderModel
    let controller: TextReaderController
    /// The last rendering; nil until the file has been read.
    private(set) var rendered: RenderedMarkdown?
    private var didAttemptLoad = false

    init(model: ReaderModel) {
        self.model = model
        self.controller = TextReaderController(model: model)
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
        controller.load(result.attributedString)
    }
}
