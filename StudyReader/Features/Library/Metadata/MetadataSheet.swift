import SwiftUI
import UniformTypeIdentifiers

/// Asks the library to open the metadata sheet for one document. `currentPageIndex` is set only by a PDF reader,
/// which enables "Use Current Page" (SPEC F-11).
struct MetadataRequest: Identifiable, Equatable {
    let documentId: String
    let currentPageIndex: Int?

    var id: String { documentId }
}

/// Edit Metadata sheet (SPEC F-11): title, author, category, tags and cover. Title, author and category are saved
/// by Save. Tags save as they change, and cover actions save at once. Logic lives in `MetadataEditorModel` and
/// `TagFieldModel`; this view only presents them.
struct MetadataSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: MetadataEditorModel
    @State private var tagModel: TagFieldModel
    @State private var isChoosingCover = false
    private let fileStore: FileStore

    init(session: AppSession, request: MetadataRequest) {
        _model = State(initialValue: MetadataEditorModel(
            documentId: request.documentId,
            currentPageIndex: request.currentPageIndex,
            session: session
        ))
        _tagModel = State(initialValue: TagFieldModel(
            target: .document(request.documentId),
            environment: session.environment
        ))
        self.fileStore = session.environment.fileStore
    }

    /// The fields and tags show only once their stored values have loaded (U2). Until then they stay laid out, hidden.
    private var isReady: Bool {
        model.hasLoaded && tagModel.hasLoadedAssignedTags
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Metadata")
                .font(.headline)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    coverPreview
                        .frame(width: 110)
                    coverButtons
                    Spacer(minLength: 0)
                }

                Form {
                    TextField("Title", text: $model.title)
                        .accessibilityLabel(Text("Title"))
                    if let titleError = model.titleError {
                        Text(titleError)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .accessibilityLabel(Text(titleError))
                    }
                    TextField("Author", text: $model.author)
                        .accessibilityLabel(Text("Author"))
                    if model.hasValidCategorySelection {
                        Picker("Category", selection: $model.categoryId) {
                            ForEach(model.categories) { category in
                                Text(category.name).tag(category.id)
                            }
                        }
                        .accessibilityLabel(Text("Category"))
                    } else {
                        // Until the categories load, the picker has no tag for its selection (T52h). Keep the row's height.
                        LabeledContent("Category") {
                            Text("")
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags")
                        .font(.subheadline.weight(.semibold))
                    TagFieldView(model: tagModel)
                }

                if let message = model.errorMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            .opacity(isReady ? 1 : 0)
            .accessibilityHidden(!isReady)
            .overlay {
                if !isReady {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading")
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel")
                Button("Save") {
                    Task {
                        if await model.save() {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isReady)
                .accessibilityLabel("Save metadata")
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            await model.load()
        }
        .fileImporter(
            isPresented: $isChoosingCover,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await model.chooseCoverImage(url) }
            }
        }
    }

    @ViewBuilder
    private var coverPreview: some View {
        if let document = model.document {
            // Keyed on `coverVersion` so the cover view reloads its image after every cover change.
            DocumentCoverView(
                document: document,
                categoryName: model.selectedCategoryName,
                fileStore: fileStore
            )
            .id(model.coverVersion)
        } else {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
        }
    }

    private var coverButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cover")
                .font(.subheadline.weight(.semibold))
            Button("Choose Image…") {
                isChoosingCover = true
            }
            .accessibilityLabel("Choose cover image")
            if model.canUseCurrentPage {
                Button("Use Current Page") {
                    Task { await model.useCurrentPageAsCover() }
                }
                .accessibilityLabel("Use current page as cover")
            }
            Button("Reset Cover") {
                Task { await model.resetCover() }
            }
            .accessibilityLabel("Reset cover to automatic")
        }
    }
}
