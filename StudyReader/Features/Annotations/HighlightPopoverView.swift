import AppKit
import SwiftUI

/// Popover for one highlight (SPEC F-06): color, text or thumbnail, note, tags, Copy and Delete.
struct HighlightPopoverView: View {
    let request: HighlightPopoverRequest
    let session: AppSession
    let onClose: () -> Void

    @State private var model: HighlightPopoverModel
    @FocusState private var focus: PopoverFocus?

    init(request: HighlightPopoverRequest, session: AppSession, onClose: @escaping () -> Void) {
        self.request = request
        self.session = session
        self.onClose = onClose
        _model = State(initialValue: HighlightPopoverModel(highlightId: request.highlightId, session: session))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ColorDotsView(settings: session.settings, selected: model.highlight?.color) { color in
                Task { await model.setColor(color) }
            }

            preview

            noteEditor

            TagFieldView(model: model.tagModel, focusOnAppear: request.focus == .tags)

            if let message = model.errorMessage ?? model.noteModel.lastError {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button {
                    copy()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .accessibilityLabel("Copy highlight")

                Spacer()

                Button(role: .destructive) {
                    Task { await model.delete() }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .accessibilityLabel("Delete highlight")
            }
        }
        .padding(12)
        .frame(width: 320)
        .task { await model.observe() }
        .task(id: model.noteModel.isLoaded) { applyRequestedFocus() }
        .onChange(of: model.isGone) { _, gone in
            if gone { onClose() }
        }
        .onDisappear {
            let note = model.noteModel
            Task { await note.flush() }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let url = model.imageURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 120, alignment: .leading)
                .accessibilityLabel("Snapshot")
        } else if let highlight = model.highlight, highlight.kind == .text {
            RichTextView(highlight.richText.isEmpty ? RichTextMarkdown.escape(highlight.text) : highlight.richText)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var noteEditor: some View {
        TextEditor(text: Bindable(model.noteModel).text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(4)
            .frame(minHeight: 4 * 18, maxHeight: 8 * 18)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .topLeading) {
                if model.noteModel.text.isEmpty {
                    Text("Add a note…")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .focused($focus, equals: .note)
            .disabled(!model.noteModel.isLoaded)
            .accessibilityLabel("Note")
    }

    /// Moves keyboard focus to the field the request asked for, once the note editor is enabled.
    private func applyRequestedFocus() {
        guard model.noteModel.isLoaded else { return }
        switch request.focus {
        case .note: focus = .note
        case .tags, .none: break
        }
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let url = model.imageURL, let data = try? Data(contentsOf: url) {
            pasteboard.setData(data, forType: .png)
        } else {
            pasteboard.setString(model.copyText, forType: .string)
        }
    }
}
