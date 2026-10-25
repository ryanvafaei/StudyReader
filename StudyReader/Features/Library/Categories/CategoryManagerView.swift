import SwiftUI

/// The sidebar Categories screen (SPEC F-01): every category with its document count. Custom categories can be
/// added, renamed and deleted. Logic lives in `CategoryManagerModel`; this view only presents it.
struct CategoryManagerView: View {
    @State private var model: CategoryManagerModel
    @State private var nameRequest: CategoryNameRequest?
    @State private var pendingDelete: CategoryUsage?

    init(session: AppSession) {
        _model = State(initialValue: CategoryManagerModel(session: session))
    }

    var body: some View {
        Group {
            if model.usage.isEmpty {
                ContentUnavailableView {
                    Label("No categories yet", systemImage: "folder")
                }
            } else {
                List(model.usage) { row in
                    CategoryRow(usage: row)
                        .contextMenu {
                            if !row.category.isBuiltin {
                                Button("Rename…") {
                                    nameRequest = .rename(row)
                                }
                                Divider()
                                Button("Delete…", role: .destructive) {
                                    pendingDelete = row
                                }
                            }
                        }
                }
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    nameRequest = .create
                } label: {
                    Label("New Category…", systemImage: "plus")
                }
                .help("Add a category")
                .accessibilityLabel("New Category")
            }
        }
        .task {
            await model.observe()
        }
        .sheet(item: $nameRequest) { request in
            CategoryNameSheet(model: model, request: request)
        }
        .confirmationDialog(
            "Delete category \"\(pendingDelete?.category.name ?? "")\"?",
            isPresented: isConfirmingDelete,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { row in
            Button("Delete", role: .destructive) {
                Task { await model.delete(id: row.id) }
            }
        } message: { row in
            Text("Its \(TagUsageFormat.documents(row.documentCount)) move to Other.")
        }
        .alert("Couldn't update categories", isPresented: isShowingError) {
            Button("OK") {
                model.dismissError()
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    /// The alert is held back while the name sheet is open, so the sheet shows its own message.
    private var isShowingError: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil && nameRequest == nil },
            set: { if !$0 { model.dismissError() } }
        )
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }
}

/// Sheet to add or rename a category.
private enum CategoryNameRequest: Identifiable {
    case create
    case rename(CategoryUsage)

    var id: String {
        switch self {
        case .create: "create"
        case .rename(let usage): "rename-\(usage.id)"
        }
    }
}

private struct CategoryRow: View {
    let usage: CategoryUsage

    var body: some View {
        HStack {
            Text(usage.category.name)
            if usage.category.isBuiltin {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Built-in category")
            }
            Spacer()
            Text(TagUsageFormat.documents(usage.documentCount))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Name entry for a category. Shows the model's error inline and closes on success.
private struct CategoryNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: CategoryManagerModel
    let request: CategoryNameRequest
    @State private var name: String

    init(model: CategoryManagerModel, request: CategoryNameRequest) {
        self.model = model
        self.request = request
        if case .rename(let usage) = request {
            _name = State(initialValue: usage.category.name)
        } else {
            _name = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            TextField("Category name", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(Text("Category name"))
                .onSubmit(save)
            if let message = model.errorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    model.dismissError()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(actionTitle, action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 340)
        .onAppear {
            model.dismissError()
        }
    }

    private var title: LocalizedStringKey {
        switch request {
        case .create: "New Category"
        case .rename: "Rename Category"
        }
    }

    private var actionTitle: LocalizedStringKey {
        switch request {
        case .create: "Add"
        case .rename: "Rename"
        }
    }

    private func save() {
        Task {
            switch request {
            case .create:
                await model.create(name: name)
            case .rename(let usage):
                await model.rename(id: usage.id, to: name)
            }
            if model.errorMessage == nil {
                dismiss()
            }
        }
    }
}
