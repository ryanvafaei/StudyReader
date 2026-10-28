import AppKit
import SwiftUI

/// What the library asks the Export sheet to open with. A new id per request, so the sheet always starts fresh.
struct ExportRequest: Identifiable, Equatable {
    let id = UUID()
    let scope: ExportScope?
}

/// Export Highlights sheet (SPEC F-21): pick a scope and options, export to a Google Doc, show the outcome.
struct ExportSheet: View {
    @State private var model: ExportSheetModel
    @Environment(\.dismiss) private var dismiss

    init(session: AppSession, request: ExportRequest) {
        _model = State(initialValue: ExportSheetModel(session: session, initialScope: request.scope))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export Highlights")
                .font(.headline)

            Form {
                scopePickers
                Section {
                    Toggle("Include highlight notes", isOn: $model.options.includeNotes)
                        .accessibilityLabel("Include highlight notes")
                    Toggle("Include document notes", isOn: $model.options.includeDocumentNotes)
                        .accessibilityLabel("Include document notes")
                    Toggle("Include image highlights as placeholders", isOn: $model.options.includeImages)
                        .accessibilityLabel("Include image highlights as placeholders")
                    Picker("Group by", selection: $model.options.groupBy) {
                        Text("Document").tag(ExportGroupBy.document)
                        Text("Tag").tag(ExportGroupBy.tag)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Group by")
                }
            }
            .formStyle(.columns)

            outcomeView

            HStack {
                if model.isExporting {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Exporting")
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Cancel")
                if model.isConfigured {
                    Button("Export") { Task { await model.export() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canExport)
                        .accessibilityLabel("Export")
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .task { await model.load() }
        .task(id: model.scope) { await model.prefillOptions() }
    }

    // MARK: - Scope

    private var scopePickers: some View {
        Section {
            Picker("Export", selection: $model.scopeKind) {
                ForEach(model.availableKinds, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .accessibilityLabel("Export scope")

            switch model.scopeKind {
            case .all:
                EmptyView()
            case .document:
                idPicker("Document") {
                    ForEach(model.documents) { Text($0.title).tag(Optional($0.id)) }
                }
            case .tag:
                idPicker("Tag") {
                    ForEach(model.tags) { Text($0.name).tag(Optional($0.id)) }
                }
            case .category:
                idPicker("Category") {
                    ForEach(model.categories) { Text($0.name).tag(Optional($0.id)) }
                }
            case .themedReview:
                idPicker("Themed review") {
                    ForEach(model.themedReviews) { Text($0.name).tag(Optional($0.id)) }
                }
            }
        }
    }

    private func idPicker<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        Picker(title, selection: $model.selectedId) {
            Text("Choose…").tag(Optional<String>.none)
            content()
        }
        .accessibilityLabel(Text(title))
    }

    // MARK: - Outcome

    @ViewBuilder
    private var outcomeView: some View {
        if !model.isConfigured {
            Text("Google export not configured")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Google export not configured")
        } else if let message = model.outcomeMessage {
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .foregroundStyle(model.exportedFileId == nil ? Color.secondary : Color.primary)
                    .accessibilityLabel(message)
                if let fileId = model.exportedFileId {
                    Button("Open in Google Docs") {
                        NSWorkspace.shared.open(ExportTargetsModel.docURL(fileId: fileId))
                    }
                    .accessibilityLabel("Open in Google Docs")
                }
                if model.isDocMissing {
                    Button("Create New Doc") { Task { await model.createNewDoc() } }
                        .accessibilityLabel("Create New Doc")
                }
            }
        }
    }
}

private extension ExportSheetModel.ScopeKind {
    var title: LocalizedStringKey {
        switch self {
        case .document: "Document"
        case .tag: "Tag"
        case .category: "Category"
        case .themedReview: "Themed review"
        case .all: "All highlights"
        }
    }
}
