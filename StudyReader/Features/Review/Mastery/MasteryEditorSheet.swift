import SwiftUI

/// "Mastery…" sheet: turn one highlight into cloze and question cards (SPEC F-16). The host presents it with
/// `.sheet(item:)`. Save has no default-action shortcut (the answer editor is multi-line); Cancel is Escape.
struct MasteryEditorSheet: View {
    let highlightId: String
    let session: AppSession
    @State private var model: MasteryEditorModel
    @Environment(\.dismiss) private var dismiss

    init(highlightId: String, session: AppSession) {
        self.highlightId = highlightId
        self.session = session
        _model = State(initialValue: MasteryEditorModel(highlightId: highlightId, environment: session.environment))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mastery")
                .font(.title2.bold())
            if model.isImageHighlight {
                imageSection
            } else {
                textSection
            }
            addButtons
            draftList
            if let draft = model.selectedDraft, case .qa(let question, let answer) = draft.kind {
                qaEditor(draft.id, question: question, answer: answer)
            }
            if let message = model.errorMessage {
                Text(message)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("mastery-error")
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(Text("Cancel"))
                    .accessibilityIdentifier("mastery-cancel")
                Button("Save") {
                    Task {
                        if await model.save() { dismiss() }
                    }
                }
                .disabled(!model.hasLoaded)
                .accessibilityLabel(Text("Save"))
                .accessibilityIdentifier("mastery-save")
            }
        }
        .padding(20)
        .frame(width: 560)
        .task { await model.load() }
    }

    private var textSection: some View {
        ClozeSelectionTextView(
            text: model.sourceText,
            tintedRanges: model.selectedClozeRanges,
            selection: Binding(get: { model.selection }, set: { model.selection = $0 })
        )
        .frame(height: 130)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
    }

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let imagePath = model.imagePath {
                MasterySnapshotView(session: session, relativePath: imagePath)
            }
            Text("Image highlights can have question cards only.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("mastery-image-note")
        }
    }

    private var addButtons: some View {
        HStack {
            if !model.isImageHighlight {
                Button("Hide Selection as New Card") { model.addCloze() }
                    .disabled(!model.canAddCloze)
                    .accessibilityLabel(Text("Hide Selection as New Card"))
                    .accessibilityIdentifier("mastery-add-cloze")
                if model.selectedClozeDraft != nil {
                    Button("Hide Selection in This Card") { model.addSelectionToSelectedCloze() }
                        .disabled(!model.canAddToSelectedCloze)
                        .accessibilityLabel(Text("Hide Selection in This Card"))
                        .accessibilityIdentifier("mastery-add-to-cloze")
                }
            }
            Button("Add Question") { model.addQuestion() }
                .accessibilityLabel(Text("Add Question"))
                .accessibilityIdentifier("mastery-add-question")
        }
    }

    private var draftList: some View {
        List(selection: Binding(get: { model.selectedDraftId }, set: { model.selectedDraftId = $0 })) {
            ForEach(model.drafts) { draft in
                row(draft)
                    .tag(draft.id)
            }
        }
        .frame(height: 120)
        .overlay {
            if model.drafts.isEmpty && model.hasLoaded {
                Text("No Mastery cards yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(Text("Mastery cards"))
        .accessibilityIdentifier("mastery-draft-list")
    }

    private func row(_ draft: MasteryDraft) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                switch draft.kind {
                case .cloze(let ranges):
                    Text("Cloze").font(.caption.bold())
                    RichTextView(ClozeText.front(model.sourceText, ranges: ranges))
                        .lineLimit(2)
                case .qa(let question, _):
                    Text("Question").font(.caption.bold())
                    Text(question.isEmpty ? String(localized: "New question") : question)
                        .lineLimit(2)
                }
                Text(draft.isSaved ? "Saved" : "New")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.remove(draft.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Remove card"))
            .accessibilityIdentifier("mastery-remove")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mastery-draft-row")
    }

    private func qaEditor(_ id: String, question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Question", text: Binding(
                get: { question },
                set: { model.updateQuestion($0, for: id) }
            ))
            .accessibilityLabel(Text("Question"))
            .accessibilityIdentifier("mastery-question-field")
            TextEditor(text: Binding(
                get: { answer },
                set: { model.updateAnswer($0, for: id) }
            ))
            .font(.body)
            .frame(minHeight: 3 * 18)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            .accessibilityLabel(Text("Answer"))
            .accessibilityIdentifier("mastery-answer-editor")
        }
    }
}

/// The PNG of an image highlight. Loaded once per path, never in `body`.
private struct MasterySnapshotView: View {
    let session: AppSession
    let relativePath: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 130)
                    .accessibilityLabel(Text("Snapshot"))
            } else {
                ProgressView()
            }
        }
        .task(id: relativePath) {
            guard let url = session.environment.fileStore.url(forRelativePath: relativePath) else { return }
            image = NSImage(contentsOf: url)
        }
    }
}
