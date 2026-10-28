import AppKit
import SwiftUI

/// The Highlights tab (SPEC F-06): the document's highlights in reading order. Clicking a row scrolls to it.
struct HighlightsPanelView: View {
    let model: ReaderModel
    @State private var panel: HighlightsPanelModel

    init(model: ReaderModel) {
        self.model = model
        _panel = State(initialValue: HighlightsPanelModel(model: model))
    }

    var body: some View {
        Group {
            if panel.isEmpty {
                ContentUnavailableView {
                    Label("No highlights yet. Select text to highlight it.", systemImage: "highlighter")
                        .labelStyle(.titleOnly)
                }
            } else {
                List {
                    ForEach(panel.sections) { section in
                        if let title = section.title {
                            Section(title) { rows(section) }
                        } else {
                            rows(section)
                        }
                    }
                }
                .listStyle(.sidebar)
                .accessibilityLabel("Highlights list")
            }
        }
        .overlay(alignment: .bottom) {
            if let message = panel.errorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
        .task { await panel.observeTagNames() }
        .task(id: model.highlights) { await panel.refresh() }
    }

    private func rows(_ section: PanelSection) -> some View {
        ForEach(section.rows) { row in
            HighlightRowView(row: row, thumbnail: row.highlight.imagePath.flatMap { panel.thumbnails[$0] })
                .contentShape(Rectangle())
                .onTapGesture { panel.select(row.id) }
                .contextMenu {
                    Button("Show in Document") { panel.select(row.id) }
                    Button("Delete", role: .destructive) {
                        Task { await panel.delete(row.id) }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(row.highlight.accessibilityExcerpt)
                .accessibilityValue(row.accessibilityDetail)
                .accessibilityIdentifier("highlight-row")
        }
    }
}

private extension Highlight {
    /// Markdown shown for the row: the edited text, else the rich text, else the plain text.
    var excerptMarkdown: String {
        if let editedText { return RichTextMarkdown.escape(editedText) }
        return richText.isEmpty ? RichTextMarkdown.escape(text) : richText
    }

    /// Row label for VoiceOver and UI tests: the plain excerpt, or "Snapshot" for an image highlight.
    var accessibilityExcerpt: String {
        if imagePath != nil { return String(localized: "Snapshot") }
        let plain = editedText ?? text
        return plain.isEmpty ? String(localized: "Highlight") : plain
    }
}

private extension PanelHighlightRow {
    /// Page and view badge as the row's accessibility value ("p. 2, PDF"); `.combine` plus the label would otherwise
    /// hide them from VoiceOver and UI tests.
    var accessibilityDetail: String {
        var parts: [String] = []
        if let page = highlight.pageIndex { parts.append(String(localized: "p. \(page + 1)")) }
        if let viewLabel { parts.append(viewLabel) }
        return parts.joined(separator: ", ")
    }
}

private struct HighlightRowView: View {
    let row: PanelHighlightRow
    let thumbnail: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(HighlightPalette.color(row.highlight.color))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                content
                if !row.highlight.note.isEmpty {
                    Text(row.highlight.note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !row.tagNames.isEmpty {
                    Text(row.tagNames.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let page = row.highlight.pageIndex {
                        Text("p. \(page + 1)")
                    }
                    if let label = row.viewLabel {
                        Text(label)
                            .padding(.horizontal, 4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if row.isOrphaned {
                    Text("Couldn't locate in document")
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 60, alignment: .leading)
                .accessibilityLabel("Snapshot")
        } else if row.highlight.imagePath == nil {
            RichTextView(row.highlight.excerptMarkdown)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
