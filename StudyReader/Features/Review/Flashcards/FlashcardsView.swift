import AppKit
import SwiftUI

/// The Flashcards screen of the Review section (SPEC F-17, F-18; ADR-0022): filter bar, the live card list and a
/// preview of the selected card with its actions. No rating, no Skip, no key handling: the only text fields are the
/// note and edit editors, and they take every key. `FlashcardsModel` owns the query, selection and actions.
struct FlashcardsView: View {
    let session: AppSession
    private let model: FlashcardsModel
    @State private var noteModel: NoteEditorModel?
    @State private var editDraft: ReviewEditDraft?
    @State private var isShowingDates = false
    @FocusState private var focusedEditor: EditorField?
    @Environment(\.openWindow) private var openWindow

    private enum EditorField: Hashable {
        case note
        case edit
    }

    init(session: AppSession) {
        self.session = session
        self.model = session.flashcardsModel()
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            HStack(spacing: 0) {
                listColumn
                    .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                detailColumn
                    .frame(minWidth: 280, idealWidth: 380, maxWidth: 460, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: model.filter) { await model.observe() }
        .task { await model.observeLookups() }
        .onChange(of: model.filter) { _, _ in
            Task { await settleNote() }
        }
        .onChange(of: model.selection) { _, _ in
            closeEditors()
        }
        .onDisappear {
            let pending = noteModel
            noteModel = nil
            editDraft = nil
            Task { await pending?.flush() }
        }
        .sheet(item: Binding(
            get: { model.masteryHighlightId.map(FlashcardsMasteryTarget.init) },
            set: { model.masteryHighlightId = $0?.id }
        )) { target in
            MasteryEditorSheet(highlightId: target.id, session: session)
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Menu(menuTitle("Document", model.filter.documentIds.count)) {
                    ForEach(model.documents) { document in
                        Toggle(document.title, isOn: Binding(
                            get: { model.filter.documentIds.contains(document.id) },
                            set: { _ in model.toggle(documentId: document.id) }
                        ))
                    }
                }
                .accessibilityLabel("Filter by document")
                .accessibilityIdentifier("flashcards-filter-document")

                Menu(menuTitle("Category", model.filter.categoryIds.count)) {
                    ForEach(model.categories) { category in
                        Toggle(category.name, isOn: Binding(
                            get: { model.filter.categoryIds.contains(category.id) },
                            set: { _ in model.toggle(categoryId: category.id) }
                        ))
                    }
                }
                .accessibilityLabel("Filter by category")
                .accessibilityIdentifier("flashcards-filter-category")

                Menu(menuTitle("Tag", model.filter.tagIds.count)) {
                    ForEach(model.tags) { tag in
                        Toggle(tag.name, isOn: Binding(
                            get: { model.filter.tagIds.contains(tag.id) },
                            set: { _ in model.toggle(tagId: tag.id) }
                        ))
                    }
                }
                .accessibilityLabel("Filter by tag")
                .accessibilityIdentifier("flashcards-filter-tag")

                if !model.filter.tagIds.isEmpty {
                    Picker("Match", selection: $model.filter.tagMode) {
                        Text("Any").tag(TagMatchMode.any)
                        Text("All").tag(TagMatchMode.all)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityLabel("Tag match mode")
                    .accessibilityIdentifier("flashcards-filter-tag-mode")
                }

                dueRangeButton

                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                ForEach(FlashcardState.allCases, id: \.self) { state in
                    Toggle(Self.name(state), isOn: Binding(
                        get: { model.filter.states.contains(state) },
                        set: { _ in model.toggle(state: state) }
                    ))
                    .toggleStyle(.button)
                    .accessibilityLabel(Text("Filter by state \(Self.name(state))"))
                    .accessibilityIdentifier("flashcards-filter-state-\(state.rawValue)")
                }
                Divider().frame(height: 16)
                ForEach(CardType.allCases, id: \.self) { type in
                    Toggle(Self.name(type), isOn: Binding(
                        get: { model.filter.cardTypes.contains(type) },
                        set: { _ in model.toggle(cardType: type) }
                    ))
                    .toggleStyle(.button)
                    .accessibilityLabel(Text("Filter by type \(Self.name(type))"))
                    .accessibilityIdentifier("flashcards-filter-type-\(type.rawValue)")
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button("Clear") { model.clearFilters() }
                    .fixedSize()
                    .disabled(!model.isFiltered)
                    .accessibilityLabel("Clear filters")
                    .accessibilityIdentifier("flashcards-clear")

                Spacer()

                Text(model.hasLoaded ? FlashcardsModel.countText(model.items.count) : "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Card count")
                    .accessibilityIdentifier("flashcards-count")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var dueRangeButton: some View {
        let isOn = model.filter.dueFrom != nil || model.filter.dueBefore != nil
        return Button {
            isShowingDates.toggle()
        } label: {
            Label("Due date", systemImage: isOn ? "calendar.badge.checkmark" : "calendar")
        }
        .fixedSize()
        .accessibilityLabel("Filter by due date")
        .accessibilityValue(isOn ? String(localized: "On") : String(localized: "Off"))
        .accessibilityIdentifier("flashcards-filter-due")
        .popover(isPresented: $isShowingDates) { datePopover }
    }

    private var datePopover: some View {
        let today = session.environment.now()
        return VStack(alignment: .leading, spacing: 10) {
            Toggle("From", isOn: Binding(
                get: { model.dueFromDay != nil },
                set: { model.dueFromDay = $0 ? today : nil }
            ))
            .accessibilityLabel("Filter from due date")
            DatePicker("From", selection: Binding(
                get: { model.dueFromDay ?? today },
                set: { model.dueFromDay = $0 }
            ), displayedComponents: .date)
                .labelsHidden()
                .disabled(model.dueFromDay == nil)
                .accessibilityLabel("From due date")

            Toggle("To", isOn: Binding(
                get: { model.dueToDay != nil },
                set: { model.dueToDay = $0 ? today : nil }
            ))
            .accessibilityLabel("Filter to due date")
            DatePicker("To", selection: Binding(
                get: { model.dueToDay ?? today },
                set: { model.dueToDay = $0 }
            ), displayedComponents: .date)
                .labelsHidden()
                .disabled(model.dueToDay == nil)
                .accessibilityLabel("To due date")
        }
        .padding(12)
        .frame(width: 220)
    }

    private func menuTitle(_ name: LocalizedStringResource, _ count: Int) -> String {
        let base = String(localized: name)
        return count == 0 ? base : "\(base) (\(count))"
    }

    // MARK: - List

    @ViewBuilder
    private var listColumn: some View {
        if !model.hasLoaded {
            Color.clear
        } else if model.items.isEmpty {
            if model.isFiltered {
                ContentUnavailableView {
                    Label("No cards match these filters", systemImage: "line.3.horizontal.decrease.circle")
                } actions: {
                    Button("Clear filters") { model.clearFilters() }
                        .accessibilityLabel("Clear filters from empty state")
                        .accessibilityIdentifier("flashcards-empty-clear")
                }
                .accessibilityIdentifier("flashcards-empty")
            } else {
                ContentUnavailableView {
                    Label("No cards yet", systemImage: "rectangle.on.rectangle")
                } description: {
                    Text("Highlight text in a document to create review cards.")
                }
                .accessibilityIdentifier("flashcards-empty")
            }
        } else {
            List(selection: selectionBinding) {
                ForEach(model.items) { item in
                    FlashcardRow(item: item, session: session)
                        .tag(item.id)
                }
            }
            .accessibilityLabel("Flashcards")
            .accessibilityIdentifier("flashcards-list")
        }
    }

    /// A selection change saves the open note first, then moves the selection.
    private var selectionBinding: Binding<String?> {
        Binding(
            get: { model.selection },
            set: { newValue in
                Task {
                    await settleNote()
                    model.selection = newValue
                }
            }
        )
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailColumn: some View {
        if let item = model.selectedItem, let content = model.selectedContent {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(content)
                    Divider()
                    bodyView(content.front, identifier: "flashcards-detail-front")
                    if let back = content.back {
                        Divider()
                        bodyView(back, identifier: "flashcards-detail-back")
                    }
                    if let source = content.source {
                        bodyView(source, identifier: "flashcards-detail-source")
                            .foregroundStyle(.secondary)
                    }
                    extras(content)
                    actions(item, content)
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
                            .accessibilityIdentifier("flashcards-error")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView("Select a card", systemImage: "rectangle.on.rectangle")
        }
    }

    private func header(_ content: ReviewCardContent) -> some View {
        HStack(spacing: 8) {
            Text(content.documentTitle)
                .font(.headline)
                .lineLimit(1)
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
                .lineLimit(1)
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
            FlashcardSnapshotView(session: session, relativePath: path, maxHeight: 320)
                .accessibilityIdentifier(identifier)
        }
    }

    @ViewBuilder
    private func extras(_ content: ReviewCardContent) -> some View {
        if !content.note.isEmpty {
            NoteMarkdownView(content.note)
                .accessibilityIdentifier("flashcards-detail-note")
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
            .accessibilityIdentifier("flashcards-detail-tags")
        }
    }

    // MARK: - Actions

    private func actions(_ item: FlashcardItem, _ content: ReviewCardContent) -> some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    Task { await toggleNote() }
                } label: {
                    Label("Note", systemImage: noteModel != nil ? "note.text.badge.plus" : "note.text")
                }
                .accessibilityLabel(Text("Note"))
                .accessibilityIdentifier("flashcards-action-note")

                Button {
                    toggleEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .disabled(item.item.highlight.kind == .image)
                .accessibilityLabel(Text("Edit"))
                .accessibilityIdentifier("flashcards-action-edit")

                if content.isEdited {
                    Toggle(isOn: $model.showOriginal) {
                        Text("Show Original")
                    }
                    .toggleStyle(.button)
                    .accessibilityLabel(Text("Show Original"))
                    .accessibilityIdentifier("flashcards-show-original")
                }
            }
            HStack(spacing: 8) {
                frequencyMenu(item.item)

                Button {
                    session.router.open(
                        documentId: item.item.highlight.documentId,
                        at: .highlight(item.item.highlight.id),
                        using: openWindow
                    )
                } label: {
                    Label("Open in Document", systemImage: "doc.text")
                }
                .accessibilityLabel(Text("Open in Document"))
                .accessibilityIdentifier("flashcards-action-open")

                Button {
                    Task {
                        await settleNote()
                        model.masteryHighlightId = model.selectedItem?.item.highlight.id
                    }
                } label: {
                    Label("Edit Mastery Cards…", systemImage: "rectangle.stack.badge.plus")
                }
                .accessibilityLabel(Text("Edit Mastery Cards"))
                .accessibilityIdentifier("flashcards-action-mastery")
            }
        }
        .buttonStyle(.bordered)
    }

    private func frequencyMenu(_ item: ReviewCardItem) -> some View {
        let current = item.card.frequencyOverride
        return Menu {
            frequencyChoice(
                Text("Category default (\(Self.name(item.categoryFrequency)))"),
                isOn: current == nil,
                value: nil
            )
            ForEach(ReviewFrequency.allCases, id: \.self) { frequency in
                frequencyChoice(Text(Self.name(frequency)), isOn: current == frequency, value: frequency)
            }
        } label: {
            Label("Frequency", systemImage: "gauge.with.dots.needle.bottom.50percent")
        }
        .menuIndicator(.visible)
        .fixedSize()
        .accessibilityLabel(Text("Frequency"))
        .accessibilityIdentifier("flashcards-action-frequency")
    }

    private func frequencyChoice(_ title: Text, isOn: Bool, value: ReviewFrequency?) -> some View {
        Button {
            Task {
                await settleNote()
                await model.setFrequency(value)
            }
        } label: {
            if isOn {
                Label { title } icon: { Image(systemName: "checkmark") }
            } else {
                title
            }
        }
    }

    // MARK: - Editors

    /// Saves the open note now, so a selection, filter or mode change doesn't lose it.
    private func settleNote() async {
        await noteModel?.flush()
    }

    private func toggleNote() async {
        if let open = noteModel {
            await open.flush()
            noteModel = nil
            focusedEditor = nil
        } else if let highlightId = model.selectedItem?.item.highlight.id {
            noteModel = NoteEditorModel(target: .highlight(highlightId), environment: session.environment)
            focusedEditor = .note
        }
    }

    private func toggleEdit() {
        if editDraft != nil {
            closeEdit()
        } else if let highlight = model.selectedItem?.item.highlight, highlight.kind == .text {
            editDraft = ReviewEditDraft(highlight: highlight)
            focusedEditor = .edit
        }
    }

    private func closeEdit() {
        editDraft = nil
        focusedEditor = nil
    }

    /// The selection changed: the editors belong to the previous card. The note is flushed first.
    private func closeEditors() {
        let pending = noteModel
        noteModel = nil
        editDraft = nil
        focusedEditor = nil
        Task { await pending?.flush() }
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
                .accessibilityIdentifier("flashcards-note-editor")
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
                .accessibilityIdentifier("flashcards-edit-editor")
            HStack {
                Button("Cancel") {
                    closeEdit()
                }
                .accessibilityLabel(Text("Cancel"))
                .accessibilityIdentifier("flashcards-edit-cancel")
                Button("Save") {
                    Task {
                        await model.editHighlightText(draft.valueToStore)
                        closeEdit()
                    }
                }
                .accessibilityLabel(Text("Save"))
                .accessibilityIdentifier("flashcards-edit-save")
            }
        }
    }

    // MARK: - Names

    fileprivate static func name(_ state: FlashcardState) -> String {
        switch state {
        case .new: String(localized: "New")
        case .learning: String(localized: "Learning")
        case .review: String(localized: "Review")
        case .suspended: String(localized: "Suspended")
        }
    }

    fileprivate static func name(_ type: CardType) -> String {
        switch type {
        case .passive: String(localized: "Passive")
        case .cloze: String(localized: "Cloze")
        case .qa: String(localized: "Q&A")
        }
    }

    private static func name(_ frequency: ReviewFrequency) -> String {
        switch frequency {
        case .off: String(localized: "Off")
        case .low: String(localized: "Low")
        case .normal: String(localized: "Normal")
        case .high: String(localized: "High")
        }
    }
}

private struct FlashcardsMasteryTarget: Identifiable {
    let id: String
}

/// One list row: type badge, front preview, document, state and due date.
private struct FlashcardRow: View {
    let item: FlashcardItem
    let session: AppSession

    var body: some View {
        let content = ReviewCardContent.make(item.item)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(FlashcardsView.name(item.item.card.cardType))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                Text(item.item.documentTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            switch content.front {
            case .markdown(let markdown):
                RichTextView(markdown)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .image(let path):
                FlashcardSnapshotView(session: session, relativePath: path, maxHeight: 48)
            }
            HStack(spacing: 6) {
                Text(FlashcardsView.name(item.state))
                Text(item.item.card.dueAt.formatted(.dateTime.day().month().year()))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.label(for: content.front)))
        .accessibilityValue(Text(valueText))
        .accessibilityIdentifier("flashcards-row")
    }

    private var valueText: String {
        let due = item.item.card.dueAt.formatted(.dateTime.day().month().year())
        return "\(FlashcardsView.name(item.item.card.cardType)), \(FlashcardsView.name(item.state)), \(due)"
    }

    private static func label(for body: ReviewCardContent.Body) -> String {
        switch body {
        case .markdown(let markdown): markdown
        case .image: String(localized: "Snapshot")
        }
    }
}

/// The PNG of an image highlight. Loaded once per path in `.task`, never in `body`.
private struct FlashcardSnapshotView: View {
    let session: AppSession
    let relativePath: String
    let maxHeight: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .leading)
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
