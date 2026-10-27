import SwiftUI

/// Library section (SPEC F-01): grid or list of documents, sort, filter, layout, context menu and delete.
/// Holds only view state (selection, pending delete). Everything else lives in `LibraryModel`.
struct LibraryView: View {
    let session: AppSession
    /// Opens the import picker (File > Import, or the toolbar button).
    let onImport: () -> Void
    @State private var model: LibraryModel
    @State private var selection: String?
    @State private var pendingDelete: LibraryItem?
    @State private var editing: MetadataRequest?
    @Environment(\.openWindow) private var openWindow

    init(session: AppSession, onImport: @escaping () -> Void) {
        self.session = session
        self.onImport = onImport
        _model = State(initialValue: LibraryModel(environment: session.environment))
    }

    var body: some View {
        content
            .navigationTitle("Library")
            .toolbar { toolbarItems }
            .background { hiddenKeyButtons }
            .task { await model.observe() }
            .task { await model.observeCategories() }
            .task { await model.observeTags() }
            .focusedSceneValue(
                \.libraryActions,
                LibraryActions(selectedDocumentId: currentSelection, editMetadata: beginEditing, exportHighlights: nil)
            )
            .sheet(item: $editing) { request in
                MetadataSheet(session: session, request: request)
            }
            .confirmationDialog(
                "Delete \"\(pendingDelete?.document.title ?? "")\"?",
                isPresented: isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let pendingDelete {
                        delete(pendingDelete)
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingDelete = nil
                }
            } message: {
                Text("This removes the document, its highlights, notes and review cards from StudyReader. The original file isn't touched.")
            }
            .alert("Library", isPresented: isShowingError) {
                Button("OK") { model.dismissError() }
            } message: {
                Text(model.errorMessage ?? "")
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.items.isEmpty {
            ContentUnavailableView {
                Label("No documents yet", systemImage: "books.vertical")
            } description: {
                Text("library.empty.hint")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } else if model.visibleItems.isEmpty {
            ContentUnavailableView {
                Label("No documents match these filters", systemImage: "line.3.horizontal.decrease.circle")
            } actions: {
                Button("Clear Filters") {
                    model.filter = LibraryFilter()
                }
            }
        } else if model.layout == .grid {
            grid
        } else {
            table
        }
    }

    /// A click on empty space (between or below the cards) clears the selection. The cards' own tap gestures win over
    /// this one, so a click on a card still selects it.
    private var grid: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(model.visibleItems) { item in
                        LibraryGridCard(
                            item: item,
                            fileStore: session.environment.fileStore,
                            coverVersion: model.coverVersions[item.id],
                            isSelected: currentSelection == item.id,
                            onRetry: { retry(item.id) }
                        )
                        .onTapGesture(count: 2) { openDocument(item.id) }
                        .onTapGesture { selection = item.id }
                        .contextMenu { menu(for: item) }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture { selection = nil }
            }
        }
    }

    private var table: some View {
        Table(of: LibraryItem.self, selection: tableSelection) {
            TableColumn("Title") { item in
                LibraryTitleCell(title: item.document.title, status: item.document.extractionStatus) {
                    retry(item.id)
                }
            }
            TableColumn("Author") { item in
                Text(item.document.author)
                    .lineLimit(1)
            }
            TableColumn("Category") { item in
                Text(item.categoryName)
                    .lineLimit(1)
            }
            TableColumn("Highlights") { item in
                Text(LibraryItemFormat.highlights(item.highlightCount))
                    .monospacedDigit()
            }
            TableColumn("Progress") { item in
                LibraryProgressRow(progress: item.document.progress)
            }
            TableColumn("Last Opened") { item in
                LibraryLastOpenedText(date: item.document.lastOpenedAt)
            }
            TableColumn("Added") { item in
                LibraryAddedText(date: item.document.addedAt)
            }
        } rows: {
            ForEach(model.visibleItems) { item in
                TableRow(item)
            }
            .dropDestination(for: URL.self) { _, urls in
                session.importCoordinator.importURLs(urls)
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let item = item(id: id) {
                menu(for: item)
            }
        } primaryAction: { ids in
            if let id = ids.first {
                openDocument(id)
            }
        }
    }

    /// Key equivalents for the library window (not visible, not in the accessibility tree, never focused).
    /// Return opens the selected document; Escape clears the selection. Both are disabled with no selection, so the
    /// key falls through as usual. Constraint: a text field added to the library window must keep Return and Escape
    /// for itself (see docs/HANDOFF.md).
    /// Return is a key equivalent (default action), so it works whichever view holds key focus: `NSTableView` takes
    /// focus after a row click and doesn't pass Return to a SwiftUI `onKeyPress`.
    private var hiddenKeyButtons: some View {
        ZStack {
            Button("Open Selected Document") { openSelection() }
                .keyboardShortcut(.defaultAction)
            Button("Clear Selection") { selection = nil }
                .keyboardShortcut(.cancelAction)
        }
        .disabled(currentSelection == nil)
        .focusable(false)
        .accessibilityHidden(true)
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 8) {
                if session.importCoordinator.isImporting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Importing")
                }
                Button(action: onImport) {
                    Label("Import", systemImage: "plus")
                }
                .help("Import files or folders")
                .accessibilityLabel("Import files or folders")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Sort", selection: $model.sort) {
                    ForEach(LibrarySort.allCases, id: \.self) { sort in
                        Text(sort.libraryTitle).tag(sort)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort documents")
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Menu("Category") {
                    Picker("Category", selection: $model.filter.categoryId) {
                        Text("Any Category").tag(Optional<String>.none)
                        ForEach(model.categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    .pickerStyle(.inline)
                }
                Menu("Tag") {
                    Picker("Tag", selection: $model.filter.tagId) {
                        Text("Any Tag").tag(Optional<String>.none)
                        ForEach(model.tags) { tag in
                            Text(tag.name).tag(Optional(tag.id))
                        }
                    }
                    .pickerStyle(.inline)
                }
                Menu("File Type") {
                    Picker("File Type", selection: $model.filter.fileType) {
                        Text("Any File Type").tag(Optional<FileType>.none)
                        Text("PDF").tag(Optional(FileType.pdf))
                        Text("Markdown").tag(Optional(FileType.markdown))
                    }
                    .pickerStyle(.inline)
                }
                Toggle("Has Highlights", isOn: $model.filter.hasHighlightsOnly)
                Divider()
                Button("Clear Filters") {
                    model.filter = LibraryFilter()
                }
                .disabled(!model.filter.isActive)
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
            .help("Filter documents")
        }

        ToolbarItem(placement: .primaryAction) {
            Picker("Layout", selection: $model.layout) {
                Label("Grid", systemImage: "square.grid.2x2")
                    .labelStyle(.iconOnly)
                    .tag(LibraryLayout.grid)
                Label("List", systemImage: "list.bullet")
                    .labelStyle(.iconOnly)
                    .tag(LibraryLayout.list)
            }
            .pickerStyle(.segmented)
            .help("Show as grid or list")
        }
    }

    // MARK: - Actions

    private func menu(for item: LibraryItem) -> LibraryItemMenu {
        LibraryItemMenu(
            item: item,
            editMetadata: beginEditing,
            onOpen: { openDocument(item.id) },
            onReveal: { model.revealOriginal(of: item.document) },
            onDelete: { pendingDelete = item }
        )
    }

    /// Opens the Edit Metadata sheet for one document (context menu or ⇧⌘M). The library has no reader page,
    /// so "Use Current Page" stays hidden here.
    private func beginEditing(_ id: String) {
        editing = MetadataRequest(documentId: id, currentPageIndex: nil)
    }

    /// Opens the document in its reader tab; an already open document's tab is selected instead (ADR-0017).
    private func openDocument(_ id: String) {
        session.router.open(documentId: id, using: openWindow)
    }

    /// Opens the selected document (Return). Does nothing with no selection.
    private func openSelection() {
        if let currentSelection {
            openDocument(currentSelection)
        }
    }

    private func retry(_ id: String) {
        Task { await model.retryExtraction(documentId: id) }
    }

    private func delete(_ item: LibraryItem) {
        pendingDelete = nil
        Task { await model.delete(documentId: item.id) }
    }

    private func item(id: String) -> LibraryItem? {
        model.visibleItems.first { $0.id == id }
    }

    /// The selection, dropped when its document is no longer listed. Computed, so nothing is written back.
    private var currentSelection: String? {
        model.existingSelection(selection)
    }

    private var tableSelection: Binding<String?> {
        Binding(
            get: { currentSelection },
            set: { selection = $0 }
        )
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDelete = nil
                }
            }
        )
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    model.dismissError()
                }
            }
        )
    }
}

private extension LibrarySort {
    var libraryTitle: LocalizedStringKey {
        switch self {
        case .dateAdded: "Date Added"
        case .lastOpened: "Last Opened"
        case .title: "Title"
        case .author: "Author"
        }
    }
}
