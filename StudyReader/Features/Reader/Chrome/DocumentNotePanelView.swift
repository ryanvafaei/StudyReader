import SwiftUI

/// The Notes tab (SPEC F-09): the document note with autosave and a rendered preview.
struct DocumentNotePanelView: View {
    @State private var noteModel: NoteEditorModel
    @State private var showsPreview = false

    init(documentId: String, session: AppSession) {
        _noteModel = State(initialValue: NoteEditorModel(target: .document(documentId), environment: session.environment))
    }

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
        .task { await noteModel.load() }
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
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(Self.blocks(noteModel.text).enumerated()), id: \.offset) { _, block in
                        Text(block)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .textSelection(.enabled)
            }
        }
        .accessibilityLabel("Note preview")
    }

    /// Parses the full Markdown syntax and returns one string per block (paragraph, list item, heading), because
    /// `Text` ignores block structure. List items get a bullet or their number.
    static func blocks(_ markdown: String) -> [AttributedString] {
        guard let parsed = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full)) else {
            return [AttributedString(markdown)]
        }
        var result: [AttributedString] = []
        var current = AttributedString()
        var currentIdentity: Int?
        func finish() {
            if !current.characters.isEmpty { result.append(current) }
            current = AttributedString()
        }
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let identity = components.first?.identity
            if identity != currentIdentity {
                finish()
                currentIdentity = identity
                current = AttributedString(listPrefix(components))
            }
            current += parsed[run.range]
        }
        finish()
        return result
    }

    private static func listPrefix(_ components: [PresentationIntent.IntentType]) -> String {
        var ordinal: Int?
        var ordered = false
        for component in components {
            switch component.kind {
            case .listItem(let value): ordinal = value
            case .orderedList: ordered = true
            default: break
            }
        }
        guard let ordinal else { return "" }
        return ordered ? "\(ordinal). " : "\u{2022} "
    }
}
