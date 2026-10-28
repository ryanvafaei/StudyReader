import AppKit
import SwiftUI

/// Detail pane for the one selected browser row: full text or snapshot, editable note and tags, color dots and
/// "Open in Document". The host sets `.id(item.id)` so each highlight gets a fresh editor.
struct HighlightDetailView: View {
    let item: HighlightListItem
    let thumbnail: NSImage?
    let session: AppSession
    let onSetColor: (HighlightColor) -> Void
    let onOpen: () -> Void

    @State private var noteModel: NoteEditorModel
    @State private var tagModel: TagFieldModel

    init(
        item: HighlightListItem,
        thumbnail: NSImage?,
        session: AppSession,
        onSetColor: @escaping (HighlightColor) -> Void,
        onOpen: @escaping () -> Void
    ) {
        self.item = item
        self.thumbnail = thumbnail
        self.session = session
        self.onSetColor = onSetColor
        self.onOpen = onOpen
        _noteModel = State(initialValue: NoteEditorModel(target: .highlight(item.id), environment: session.environment))
        _tagModel = State(initialValue: TagFieldModel(target: .highlight(item.id), environment: session.environment))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ColorDotsView(settings: session.settings, selected: item.highlight.color, onPick: onSetColor)

                preview

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                noteEditor

                TagFieldView(model: tagModel)

                if let message = noteModel.lastError {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                Button {
                    onOpen()
                } label: {
                    Label("Open in Document", systemImage: "arrow.up.right.square")
                }
                .accessibilityLabel("Open in Document")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await noteModel.load() }
        .task { await tagModel.observe() }
        .onDisappear {
            let note = noteModel
            Task { await note.flush() }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 240, alignment: .leading)
                .accessibilityLabel("Snapshot")
        } else if item.highlight.imagePath == nil {
            RichTextView(item.highlight.listExcerptMarkdown)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var subtitle: String {
        var parts = [item.documentTitle]
        if let page = item.highlight.pageIndex { parts.append(String(localized: "p. \(page + 1)")) }
        parts.append(item.highlight.createdAt.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }

    private var noteEditor: some View {
        TextEditor(text: Bindable(noteModel).text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(4)
            .frame(minHeight: 4 * 18, maxHeight: 10 * 18)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .topLeading) {
                if noteModel.text.isEmpty {
                    Text("Add a note…")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .disabled(!noteModel.isLoaded)
            .accessibilityLabel("Note")
            .accessibilityIdentifier("highlight-detail-note")
    }
}
