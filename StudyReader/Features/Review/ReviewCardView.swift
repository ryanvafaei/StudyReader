import SwiftUI

/// One review card: header, front, optional back, rating row. Keys go through the focused card only (ADR-0022).
struct ReviewCardView: View {
    let model: ReviewSessionModel
    let session: AppSession
    @FocusState private var isFocused: Bool
    @FocusState private var focusedEditor: EditorField?
    @State private var noteModel: NoteEditorModel?
    @State private var editDraft: ReviewEditDraft?

    private enum EditorField: Hashable {
        case note
        case edit
    }

    var body: some View {
        ScrollView {
            if let content = model.content {
                VStack(alignment: .leading, spacing: 14) {
                    header(content)
                    Divider()
                    bodyView(content.front, identifier: "review-card-front")
                    if !content.needsReveal {
                        extras(content)
                    } else if model.isRevealed {
                        Divider()
                        if let back = content.back {
                            bodyView(back, identifier: "review-card-back")
                        }
                        if let source = content.source {
                            bodyView(source, identifier: "review-card-source")
                                .foregroundStyle(.secondary)
                        }
                        extras(content)
                    } else {
                        revealButton
                    }
                    ratingRow
                    ReviewActionsBar(
                        model: model,
                        session: session,
                        isNoteOpen: noteModel != nil,
                        isEditOpen: editDraft != nil,
                        onToggleNote: { Task { await toggleNote() } },
                        onToggleEdit: toggleEdit,
                        onFrequency: { value in
                            Task {
                                await settleNote()
                                await model.setFrequency(value)
                            }
                        },
                        onSkip: {
                            Task {
                                if noteModel != nil {
                                    await settleNote()
                                    await model.reloadCurrent()
                                }
                                model.skip()
                            }
                        }
                    )
                    if let noteModel {
                        noteEditor(noteModel)
                    }
                    if let editDraft {
                        editEditor(editDraft)
                    }
                    if let message = model.errorMessage {
                        Text(LocalizedStringKey(message))
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("review-error")
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onChange(of: model.current?.id) { _, _ in
            noteModel = nil
            editDraft = nil
            focusedEditor = nil
            isFocused = true
        }
        .onDisappear {
            let pending = noteModel
            Task {
                await pending?.flush()
                await model.reloadCurrent()
            }
        }
        .onKeyPress(characters: CharacterSet(charactersIn: " 1234"), phases: .down) { press in
            guard noteModel == nil, editDraft == nil else { return .ignored }
            guard let key = press.characters.first,
                  let action = model.action(forKey: key)
            else { return .ignored }
            Task {
                if case .rate = action {
                    await settleNote()
                }
                await model.perform(action)
            }
            return .handled
        }
    }

    private func header(_ content: ReviewCardContent) -> some View {
        HStack(spacing: 8) {
            Text(content.documentTitle)
                .font(.headline)
                .lineLimit(1)
                .accessibilityIdentifier("review-document-title")
            if let page = content.pageNumber {
                Text("p. \(page)")
                    .foregroundStyle(.secondary)
            }
            Circle()
                .fill(HighlightPalette.color(content.color))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(session.settings.label(for: content.color))
                .foregroundStyle(.secondary)
            Spacer()
            Text(model.progressText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityIdentifier("review-progress")
        }
    }

    @ViewBuilder
    private func bodyView(_ body: ReviewCardContent.Body, identifier: String) -> some View {
        switch body {
        case .markdown(let markdown):
            RichTextView(markdown)
                .font(.title3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .accessibilityIdentifier(identifier)
        case .image(let path):
            ReviewSnapshotView(session: session, relativePath: path)
                .accessibilityIdentifier(identifier)
        }
    }

    @ViewBuilder
    private func extras(_ content: ReviewCardContent) -> some View {
        if !content.note.isEmpty {
            NoteMarkdownView(content.note)
                .accessibilityIdentifier("review-card-note")
        }
        if !content.tagNames.isEmpty {
            HStack(spacing: 6) {
                ForEach(content.tagNames, id: \.self) { name in
                    Text("#\(name)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            .accessibilityIdentifier("review-card-tags")
        }
    }

    /// Saves the open note now, so the next card change or write sees it.
    private func settleNote() async {
        await noteModel?.flush()
    }

    private func toggleNote() async {
        if let open = noteModel {
            await open.flush()
            noteModel = nil
            await model.reloadCurrent()
            focusedEditor = nil
            isFocused = true
        } else if let highlightId = model.current?.highlight.id {
            noteModel = NoteEditorModel(target: .highlight(highlightId), environment: session.environment)
            isFocused = false
            focusedEditor = .note
        }
    }

    private func toggleEdit() {
        if editDraft != nil {
            closeEdit()
        } else if let highlight = model.current?.highlight, highlight.kind == .text {
            editDraft = ReviewEditDraft(highlight: highlight)
            isFocused = false
            focusedEditor = .edit
        }
    }

    private func closeEdit() {
        editDraft = nil
        focusedEditor = nil
        isFocused = true
    }

    private func noteEditor(_ editor: NoteEditorModel) -> some View {
        @Bindable var editor = editor
        return VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $editor.text)
                .font(.body)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .focused($focusedEditor, equals: .note)
                .accessibilityLabel(Text("Note"))
                .accessibilityIdentifier("review-note-editor")
            if let message = editor.lastError {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task { await editor.load() }
    }

    private func editEditor(_ draft: ReviewEditDraft) -> some View {
        @Bindable var draft = draft
        return VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $draft.text)
                .font(.body)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .focused($focusedEditor, equals: .edit)
                .accessibilityLabel(Text("Highlight text"))
                .accessibilityIdentifier("review-edit-editor")
            HStack {
                Button("Cancel") {
                    closeEdit()
                }
                .accessibilityLabel(Text("Cancel"))
                .accessibilityIdentifier("review-edit-cancel")
                Button("Save") {
                    Task {
                        await model.editHighlightText(draft.valueToStore)
                        closeEdit()
                    }
                }
                .disabled(model.isBusy)
                .accessibilityLabel(Text("Save"))
                .accessibilityIdentifier("review-edit-save")
            }
        }
    }

    private var revealButton: some View {
        Button {
            model.reveal()
        } label: {
            HStack {
                Text("Show Answer")
                Text("Space")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(Text("Show Answer"))
        .accessibilityIdentifier("review-reveal")
    }

    private var ratingRow: some View {
        HStack(spacing: 10) {
            ForEach(model.ratingButtons) { button in
                Button {
                    Task {
                        await settleNote()
                        await model.rate(button.rating)
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text(button.title)
                        Text(String(button.key))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 64)
                }
                .disabled(!model.canRate)
                .accessibilityLabel(Text(button.title))
                .accessibilityIdentifier(Self.identifier(for: button.rating))
            }
        }
        .padding(.top, 6)
    }

    private static func identifier(for rating: ReviewRating) -> String {
        switch rating {
        case .again: "review-rate-again"
        case .hard: "review-rate-hard"
        case .good: "review-rate-good"
        case .easy: "review-rate-easy"
        }
    }
}

/// The PNG of an image highlight. Loaded once per path, never in `body`.
private struct ReviewSnapshotView: View {
    let session: AppSession
    let relativePath: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 360)
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
