import SwiftUI

/// Create or edit one themed review (SPEC F-20). Presented by the Themed Reviews section (T124) with `.sheet(item:)`.
/// Save is the default action (Return) and Cancel the cancel action (Escape); the sheet handles no other keys.
struct ThemedReviewEditorSheet: View {
    @State private var model: ThemedReviewEditorModel
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    init(reviewId: String?, environment: AppEnvironment) {
        _model = State(initialValue: ThemedReviewEditorModel(reviewId: reviewId, environment: environment))
    }

    var body: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $model.draft.name, prompt: Text("e.g. ML1 exam week"))
                        .accessibilityLabel("Themed review name")
                        .accessibilityIdentifier("themed-editor-name")
                }

                Section {
                    tagsRow
                    documentsRow
                    categoriesRow
                    colorsRow
                } header: {
                    Text("Highlights")
                } footer: {
                    Text("Leave a group empty to include everything.")
                }

                Section("Session") {
                    Stepper(value: $model.draft.cardsPerSession, in: 5...100) {
                        Text("Cards per session: \(model.draft.cardsPerSession)")
                    }
                    .accessibilityLabel("Cards per session")
                    .accessibilityIdentifier("themed-editor-cards")

                    Picker("Order", selection: $model.draft.orderMode) {
                        Text("Due first, then least recently reviewed").tag(ReviewOrderMode.dueFirst)
                        Text("Random").tag(ReviewOrderMode.random)
                    }
                    .accessibilityLabel("Order")
                    .accessibilityIdentifier("themed-editor-order")
                }

                Section("Schedule") {
                    Picker("Repeat", selection: $model.intervalKind) {
                        Text("Every day").tag(ReviewInterval.Kind.daily)
                        Text("Every N days").tag(ReviewInterval.Kind.everyNDays)
                        Text("On weekdays").tag(ReviewInterval.Kind.weekdays)
                    }
                    .accessibilityLabel("Repeat")
                    .accessibilityIdentifier("themed-editor-repeat")

                    switch model.intervalKind {
                    case .daily:
                        EmptyView()
                    case .everyNDays:
                        Stepper(value: $model.everyNDays, in: 1...365) {
                            Text("Every \(model.everyNDays) days")
                        }
                        .accessibilityLabel("Days between sessions")
                        .accessibilityIdentifier("themed-editor-every-n")
                    case .weekdays:
                        weekdayRow
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let message = model.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .accessibilityIdentifier("themed-editor-error")
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Cancel")
                    .accessibilityIdentifier("themed-editor-cancel")
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSave || isSaving)
                    .accessibilityLabel("Save")
                    .accessibilityIdentifier("themed-editor-save")
            }
            .padding(12)
        }
        .frame(width: 520)
        .navigationTitle(model.isNew ? "New Themed Review" : "Edit Themed Review")
        .task { await model.load() }
        .task { await model.observeLookups() }
    }

    // MARK: Rows

    private var tagsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Tags") {
                Menu(summary(model.draft.filter.tagIds.count)) {
                    ForEach(model.tags) { tag in
                        Toggle(tag.name, isOn: Binding(
                            get: { model.draft.filter.tagIds.contains(tag.id) },
                            set: { _ in model.toggle(tagId: tag.id) }
                        ))
                    }
                }
                .accessibilityLabel("Tags")
                .accessibilityIdentifier("themed-editor-tags")
            }
            if model.draft.filter.tagIds.count >= 2 {
                Picker("Match", selection: $model.draft.filter.tagMode) {
                    Text("Any").tag(TagMatchMode.any)
                    Text("All").tag(TagMatchMode.all)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Tag match mode")
                .accessibilityIdentifier("themed-editor-tag-mode")
            }
        }
    }

    private var documentsRow: some View {
        LabeledContent("Documents") {
            Menu(summary(model.draft.filter.documentIds.count)) {
                ForEach(model.documents) { document in
                    Toggle(document.title, isOn: Binding(
                        get: { model.draft.filter.documentIds.contains(document.id) },
                        set: { _ in model.toggle(documentId: document.id) }
                    ))
                }
            }
            .accessibilityLabel("Documents")
            .accessibilityIdentifier("themed-editor-documents")
        }
    }

    private var categoriesRow: some View {
        LabeledContent("Categories") {
            Menu(summary(model.draft.filter.categoryIds.count)) {
                ForEach(model.categories) { category in
                    Toggle(category.name, isOn: Binding(
                        get: { model.draft.filter.categoryIds.contains(category.id) },
                        set: { _ in model.toggle(categoryId: category.id) }
                    ))
                }
            }
            .accessibilityLabel("Categories")
            .accessibilityIdentifier("themed-editor-categories")
        }
    }

    private var colorsRow: some View {
        LabeledContent("Colors") {
            HStack(spacing: 4) {
                ForEach(HighlightColor.allCases, id: \.self) { color in
                    Toggle(HighlightPalette.title(color), isOn: Binding(
                        get: { model.draft.filter.colors.contains(color) },
                        set: { _ in model.toggle(color: color) }
                    ))
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .accessibilityLabel(HighlightPalette.title(color))
                    .accessibilityIdentifier("themed-editor-color-\(String(describing: color))")
                }
            }
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(model.weekdayOrder, id: \.self) { weekday in
                Toggle(model.weekdaySymbol(weekday), isOn: Binding(
                    get: { model.isSelected(weekday: weekday) },
                    set: { _ in model.toggle(weekday: weekday) }
                ))
                .toggleStyle(.button)
                .controlSize(.small)
                .accessibilityLabel(model.weekdaySymbol(weekday))
                .accessibilityIdentifier("themed-editor-weekday-\(weekday)")
            }
        }
    }

    private func summary(_ count: Int) -> String {
        count == 0 ? String(localized: "All") : String(localized: "\(count) selected")
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            let saved = await model.save()
            isSaving = false
            if saved { dismiss() }
        }
    }
}
