import SwiftUI

/// The sidebar Tags screen (SPEC F-10): every tag with its usage counts, and rename, merge and delete.
/// Logic lives in `TagManagerModel`; this view only presents it.
struct TagManagerView: View {
    @State private var model: TagManagerModel
    @State private var renaming: TagUsage?
    @State private var pendingMerge: MergeRequest?
    @State private var pendingDelete: TagUsage?

    init(session: AppSession) {
        _model = State(initialValue: TagManagerModel(environment: session.environment))
    }

    var body: some View {
        Group {
            if model.usage.isEmpty {
                ContentUnavailableView {
                    Label("No tags yet", systemImage: "tag")
                } description: {
                    Text("Add tags to highlights or documents, or write #tag in a highlight note.")
                }
            } else {
                List(model.usage) { row in
                    TagRow(usage: row)
                        .contextMenu {
                            Button("Rename…") {
                                renaming = row
                            }
                            Menu("Merge into…") {
                                ForEach(model.usage.filter { $0.id != row.id }) { target in
                                    Button(target.tag.name) {
                                        pendingMerge = MergeRequest(source: row, target: target)
                                    }
                                }
                            }
                            .disabled(model.usage.count < 2)
                            Divider()
                            Button("Delete…", role: .destructive) {
                                pendingDelete = row
                            }
                        }
                }
            }
        }
        .navigationTitle("Tags")
        .task {
            await model.observe()
        }
        .sheet(item: $renaming) { tag in
            RenameTagSheet(model: model, tag: tag.tag)
        }
        .confirmationDialog(
            "Merge \"\(pendingMerge?.source.tag.name ?? "")\" into \"\(pendingMerge?.target.tag.name ?? "")\"?",
            isPresented: isConfirmingMerge,
            titleVisibility: .visible,
            presenting: pendingMerge
        ) { request in
            Button("Merge") {
                Task { await model.merge(sourceId: request.source.id, into: request.target.id) }
            }
        } message: { request in
            Text("Highlights and documents with \"\(request.source.tag.name)\" get \"\(request.target.tag.name)\" instead. The tag \"\(request.source.tag.name)\" is deleted. Nothing else is removed.")
        }
        .confirmationDialog(
            "Delete tag \"\(pendingDelete?.tag.name ?? "")\"?",
            isPresented: isConfirmingDelete,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { tag in
            Button("Delete", role: .destructive) {
                Task { await model.delete(tagId: tag.id) }
            }
        } message: { tag in
            Text("It is removed from \(LibraryItemFormat.highlights(tag.highlightCount)) and \(TagUsageFormat.documents(tag.documentCount)). They aren't deleted.")
        }
        .alert("Couldn't update tags", isPresented: isShowingError) {
            Button("OK") {
                model.dismissError()
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    /// The alert is held back while the rename sheet is open, so the sheet shows its own message.
    private var isShowingError: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil && renaming == nil },
            set: { if !$0 { model.dismissError() } }
        )
    }

    private var isConfirmingMerge: Binding<Bool> {
        Binding(
            get: { pendingMerge != nil },
            set: { if !$0 { pendingMerge = nil } }
        )
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }
}

/// A pending merge: `source` is merged into `target`.
private struct MergeRequest: Identifiable {
    let source: TagUsage
    let target: TagUsage

    var id: String { "\(source.id)>\(target.id)" }
}

private struct TagRow: View {
    let usage: TagUsage

    var body: some View {
        HStack {
            Text(usage.tag.name)
            Spacer()
            Text("\(LibraryItemFormat.highlights(usage.highlightCount)), \(TagUsageFormat.documents(usage.documentCount))")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Small text form for the rename sheet. Shows the model's error inline and closes on success.
private struct RenameTagSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: TagManagerModel
    let tag: LibraryTag
    @State private var name: String

    init(model: TagManagerModel, tag: LibraryTag) {
        self.model = model
        self.tag = tag
        _name = State(initialValue: tag.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename tag")
                .font(.headline)
            TextField("Tag name", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(Text("Tag name"))
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
                Button("Rename", action: save)
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

    private func save() {
        Task {
            await model.rename(tagId: tag.id, to: name)
            if model.errorMessage == nil {
                dismiss()
            }
        }
    }
}

/// Count labels for tag rows and the delete confirmation. Highlight wording is shared with the library.
enum TagUsageFormat {
    static func documents(_ count: Int) -> String {
        count == 1 ? String(localized: "1 document") : String(localized: "\(count) documents")
    }
}
