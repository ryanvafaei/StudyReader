import AppKit
import PDFKit
import SwiftUI

/// The PDF reader of one tab (SPEC F-04): the PDF view, an optional thumbnails column and a bottom bar with the page
/// field and the outline. The controller is created on first appearance, so a re-evaluated parent doesn't build a
/// second `PDFView`. PDFKit types stay inside this folder.
struct PDFReaderView: View {
    let model: ReaderModel
    @State private var controller: PDFReaderController?

    var body: some View {
        Group {
            if let controller {
                PDFReaderContent(controller: controller, model: model)
            } else {
                Color.clear
            }
        }
        .task {
            if controller == nil {
                controller = PDFReaderController(model: model)
            }
        }
    }
}

private struct PDFReaderContent: View {
    let controller: PDFReaderController
    let model: ReaderModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if controller.showsThumbnails {
                    PDFThumbnailHost(controller: controller)
                        .frame(width: 140)
                    Divider()
                }
                PDFViewHost(controller: controller)
            }
            Divider()
            PDFBottomBar(controller: controller)
        }
        .task {
            // The view is in the window by now, so the saved position is restored against a real layout.
            if !controller.didAttemptLoad, let url = model.fileURL {
                controller.load(url: url)
            }
        }
        .task(id: model.pendingLocation) {
            controller.applyPendingLocation()
        }
        .onChange(of: model.highlights) {
            controller.highlightsChanged()
        }
        .onChange(of: model.session.settings.invertPDFInDarkMode, initial: true) { _, enabled in
            controller.setInversionEnabled(enabled)
        }
    }
}

/// Puts the controller's `StudyPDFView` into SwiftUI.
private struct PDFViewHost: NSViewRepresentable {
    let controller: PDFReaderController

    func makeNSView(context: Context) -> StudyPDFView {
        controller.pdfView
    }

    func updateNSView(_ nsView: StudyPDFView, context: Context) {}
}

/// Page thumbnails bound to the controller's PDF view; clicking one jumps there.
private struct PDFThumbnailHost: NSViewRepresentable {
    let controller: PDFReaderController

    func makeNSView(context: Context) -> PDFThumbnailView {
        let thumbnails = PDFThumbnailView(frame: .zero)
        thumbnails.pdfView = controller.pdfView
        thumbnails.thumbnailSize = CGSize(width: 96, height: 124)
        thumbnails.maximumNumberOfColumns = 1
        return thumbnails
    }

    func updateNSView(_ nsView: PDFThumbnailView, context: Context) {}
}

/// "Page [n] of N" and the outline button.
private struct PDFBottomBar: View {
    let controller: PDFReaderController
    @State private var pageText = ""
    @State private var isOutlinePresented = false

    var body: some View {
        HStack(spacing: 8) {
            if !controller.outline.isEmpty {
                Button {
                    isOutlinePresented = true
                } label: {
                    Label("Outline", systemImage: "list.bullet.indent")
                        .labelStyle(.iconOnly)
                }
                .help("Show the table of contents")
                .accessibilityLabel("Outline")
                .popover(isPresented: $isOutlinePresented) {
                    PDFOutlineList(items: controller.outline) { pageIndex in
                        controller.go(toPage: pageIndex)
                        isOutlinePresented = false
                    }
                }
            }
            Spacer()
            Text("Page")
            TextField("Page", text: $pageText)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
                .accessibilityLabel("Page number")
                .onSubmit(jumpToTypedPage)
            Text("of \(controller.pageCount)")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .onChange(of: controller.displayedPageIndex, initial: true) { _, index in
            pageText = String(index + 1)
        }
    }

    /// Return in the field: jumps to the page, or puts the current page number back for invalid input.
    private func jumpToTypedPage() {
        let typed = pageText.trimmingCharacters(in: .whitespaces)
        guard let number = Int(typed), (1...max(controller.pageCount, 1)).contains(number) else {
            pageText = String(controller.displayedPageIndex + 1)
            return
        }
        pageText = String(number)
        controller.go(toPage: number - 1)
        controller.focusDocument()
    }
}

private struct PDFOutlineList: View {
    let items: [PDFOutlineItem]
    let onSelect: (Int) -> Void

    var body: some View {
        List(items, children: \.children) { item in
            Button {
                if let pageIndex = item.pageIndex {
                    onSelect(pageIndex)
                }
            } label: {
                Text(item.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(item.pageIndex == nil)
        }
        .frame(width: 320, height: 400)
    }
}
