import SwiftUI

/// The Notes tab (SPEC F-09): the document note with autosave and a rendered preview.
struct DocumentNotePanelView: View {
    /// Owned by the side panel so unsaved text survives switching tabs.
    let noteModel: NoteEditorModel
    @State private var showsPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsPreview {
                preview
            } else {
                editor
            }
            if let message = noteModel.lastError {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Toggle("Preview", isOn: $showsPreview)
                .toggleStyle(.checkbox)
                .accessibilityLabel("Preview")
        }
        .task {
            if !noteModel.isLoaded { await noteModel.load() }
        }
        .onDisappear {
            let note = noteModel
            Task { await note.flush() }
        }
    }

    private var editor: some View {
        TextEditor(text: Bindable(noteModel).text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .topLeading) {
                if noteModel.text.isEmpty {
                    Text("Notes for this document…")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .disabled(!noteModel.isLoaded)
            .accessibilityLabel("Document note")
    }

    @ViewBuilder
    private var preview: some View {
        ScrollView {
            if noteModel.text.isEmpty {
                Text("No notes yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                NoteMarkdownView(noteModel.text, style: .regular)
                .textSelection(.enabled)
            }
        }
        .accessibilityLabel("Note preview")
    }
}
