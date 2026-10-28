import AppKit
import SwiftUI

/// The Highlights section (SPEC F-13): filter bar, the live list, a bulk-action bar for several selected rows and a
/// detail pane for one. Holds no logic: `HighlightsBrowserModel` owns the query, selection and actions.
struct HighlightsBrowserView: View {
    let session: AppSession
    @State private var model: HighlightsBrowserModel
    @State private var pendingDelete: Set<String> = []
    @State private var isShowingDates = false
    @State private var isAddingTag = false
    @State private var tagQuery = ""
    @Environment(\.openWindow) private var openWindow

    init(session: AppSession) {
        self.session = session
        _model = State(initialValue: HighlightsBrowserModel(environment: session.environment))
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            // Not an HSplitView: it reports its own small height and stays centred instead of filling the column.
            HStack(spacing: 0) {
                listColumn
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                detailColumn
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 360, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Highlights")
        .task(id: model.query) { await model.observe() }
        .task { await model.observeLookups() }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(
                get: { !pendingDelete.isEmpty },
                set: { if !$0 { pendingDelete = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let ids = pendingDelete
                pendingDelete = []
                Task { await model.delete(ids: ids) }
            }
            Button("Cancel", role: .cancel) { pendingDelete = [] }
        }
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
    }

    private var deleteTitle: String {
        HighlightsBrowserModel.deleteTitle(count: pendingDelete.count)
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

                Menu(menuTitle("Category", model.filter.categoryIds.count)) {
                    ForEach(model.categories) { category in
                        Toggle(category.name, isOn: Binding(
                            get: { model.filter.categoryIds.contains(category.id) },
                            set: { _ in model.toggle(categoryId: category.id) }
                        ))
                    }
                }
                .accessibilityLabel("Filter by category")

                Menu(menuTitle("Tag", model.filter.tagIds.count)) {
                    ForEach(model.tags) { tag in
                        Toggle(tag.name, isOn: Binding(
                            get: { model.filter.tagIds.contains(tag.id) },
                            set: { _ in model.toggle(tagId: tag.id) }
                        ))
                    }
                }
                .accessibilityLabel("Filter by tag")

                if !model.filter.tagIds.isEmpty {
                    Picker("Match", selection: $model.filter.tagMode) {
                        Text("Any").tag(TagMatchMode.any)
                        Text("All").tag(TagMatchMode.all)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityLabel("Tag match mode")
                }

                Menu(menuTitle("View", model.filter.views.count)) {
                    ForEach(ReaderViewKind.allCases, id: \.self) { kind in
                        Toggle(Self.title(kind), isOn: Binding(
                            get: { model.filter.views.contains(kind) },
                            set: { _ in model.toggle(view: kind) }
                        ))
                    }
                }
                .accessibilityLabel("Filter by view")

                Spacer()
            }

            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    ForEach(HighlightColor.allCases, id: \.self) { color in
                        Button {
                            model.toggle(color: color)
                        } label: {
                            Circle()
                                .fill(HighlightPalette.color(color))
                                .frame(width: 14, height: 14)
                                .overlay(Circle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
                                .overlay {
                                    if model.filter.colors.contains(color) {
                                        Circle().strokeBorder(Color.primary, lineWidth: 2).padding(-3)
                                    }
                                }
                                .padding(5)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(HighlightPalette.title(color))
                        .accessibilityLabel(Text("Filter by \(HighlightPalette.title(color))"))
                        .accessibilityAddTraits(model.filter.colors.contains(color) ? .isSelected : [])
                    }
                }

                Picker("Note", selection: $model.filter.hasNote) {
                    Text("Any note").tag(Bool?.none)
                    Text("With note").tag(Bool?.some(true))
                    Text("Without note").tag(Bool?.some(false))
                }
                .fixedSize()
                .accessibilityLabel("Filter by note")

                Button {
                    isShowingDates.toggle()
                } label: {
                    Label(
                        model.filter.createdFrom != nil || model.filter.createdBefore != nil
                            ? String(localized: "Date range (on)") : String(localized: "Date range"),
                        systemImage: "calendar"
                    )
                }
                .accessibilityLabel("Filter by date")
                .popover(isPresented: $isShowingDates) { datePopover }

                Picker("Sort", selection: $model.sort) {
                    Text("Newest first").tag(HighlightBrowserSort.createdNewest)
                    Text("Document and position").tag(HighlightBrowserSort.documentPosition)
                    Text("Color").tag(HighlightBrowserSort.color)
                }
                .fixedSize()
                .accessibilityLabel("Sort highlights")

                Button("Clear") { model.clearFilters() }
                    .disabled(!model.isFiltered)
                    .accessibilityLabel("Clear filters")

                Spacer()

                Text(countText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var countText: String {
        model.hasLoaded ? HighlightsBrowserModel.countText(model.items.count) : ""
    }

    private func menuTitle(_ name: LocalizedStringResource, _ count: Int) -> String {
        let base = String(localized: name)
        return count == 0 ? base : "\(base) (\(count))"
    }

    private static func title(_ kind: ReaderViewKind) -> String {
        switch kind {
        case .pdf: String(localized: "PDF view")
        case .text: String(localized: "Text view")
        case .markdown: String(localized: "Markdown")
        }
    }

    private var datePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("From", isOn: Binding(
                get: { model.fromDay != nil },
                set: { model.fromDay = $0 ? model.today : nil }
            ))
            .accessibilityLabel("Filter from date")
            DatePicker("From", selection: Binding(
                get: { model.fromDay ?? model.today },
                set: { model.fromDay = $0 }
            ), displayedComponents: .date)
                .labelsHidden()
                .disabled(model.fromDay == nil)
                .accessibilityLabel("From date")

            Toggle("To", isOn: Binding(
                get: { model.toDay != nil },
                set: { model.toDay = $0 ? model.today : nil }
            ))
            .accessibilityLabel("Filter to date")
            DatePicker("To", selection: Binding(
                get: { model.toDay ?? model.today },
                set: { model.toDay = $0 }
            ), displayedComponents: .date)
                .labelsHidden()
                .disabled(model.toDay == nil)
                .accessibilityLabel("To date")
        }
        .padding(12)
        .frame(width: 220)
    }

    // MARK: - List

    private var listColumn: some View {
        VStack(spacing: 0) {
            if model.selection.count > 1 {
                bulkBar
                Divider()
            }
            listContent
        }
    }

    @ViewBuilder
    private var listContent: some View {
        @Bindable var model = model
        if !model.hasLoaded {
            Color.clear
        } else if model.items.isEmpty {
            if model.isFiltered {
                ContentUnavailableView {
                    Label("No highlights match these filters", systemImage: "line.3.horizontal.decrease.circle")
                } actions: {
                    Button("Clear filters") { model.clearFilters() }
                        .accessibilityLabel("Clear filters from empty state")
                }
            } else {
                ContentUnavailableView {
                    Label("No highlights yet", systemImage: "highlighter")
                } description: {
                    Text("Select text in a document to highlight it.")
                }
            }
        } else {
            List(model.items, selection: $model.selection) { item in
                HighlightBrowserRow(item: item, thumbnail: item.highlight.imagePath.flatMap { model.thumbnails[$0] })
                    .tag(item.id)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(item.highlight.listAccessibilityExcerpt)
                    .accessibilityValue(item.accessibilityDetail)
                    .accessibilityIdentifier("highlight-row")
            }
            .accessibilityLabel("Highlights list")
            .contextMenu(forSelectionType: String.self) { ids in
                if ids.count == 1, let id = ids.first {
                    Button("Open in Document") { open(id) }
                }
                if !ids.isEmpty {
                    Button("Delete…", role: .destructive) { pendingDelete = ids }
                }
            } primaryAction: { ids in
                if ids.count == 1, let id = ids.first { open(id) }
            }
        }
    }

    // MARK: - Bulk actions

    private var bulkBar: some View {
        HStack(spacing: 10) {
            Text("\(model.selection.count) selected")
                .font(.callout)
                .accessibilityLabel("Selected")
                .accessibilityValue("\(model.selection.count)")

            Button("Add Tag…") {
                tagQuery = ""
                isAddingTag = true
            }
            .accessibilityLabel("Add tag to selection")
            .popover(isPresented: $isAddingTag) { addTagPopover }

            Menu("Remove Tag") {
                ForEach(model.tagsInSelection) { tag in
                    Button(tag.name) { Task { await model.removeTag(tag.id) } }
                }
            }
            .disabled(model.tagsInSelection.isEmpty)
            .fixedSize()
            .accessibilityLabel("Remove tag from selection")

            Menu("Color") {
                ForEach(HighlightColor.allCases, id: \.self) { color in
                    Button {
                        Task { await model.setColor(color) }
                    } label: {
                        Label {
                            Text(HighlightPalette.title(color))
                        } icon: {
                            Image(nsImage: HighlightPalette.swatchImage(color))
                        }
                    }
                }
            }
            .fixedSize()
            .accessibilityLabel("Change color of selection")

            Spacer()

            Button("Delete…", role: .destructive) { pendingDelete = model.selection }
                .accessibilityLabel("Delete selection")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var addTagPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Tag name", text: $tagQuery)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Tag name")
                .onSubmit { addTag(tagQuery) }
            ForEach(model.suggestions(for: tagQuery)) { tag in
                Button(tag.name) { addTag(tag.name) }
                    .buttonStyle(.link)
                    .accessibilityLabel(Text("Add tag \(tag.name)"))
            }
        }
        .padding(12)
        .frame(width: 220)
    }

    private func addTag(_ name: String) {
        isAddingTag = false
        Task { await model.addTag(named: name) }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailColumn: some View {
        if let item = model.detailItem {
            HighlightDetailView(
                item: item,
                thumbnail: item.highlight.imagePath.flatMap { model.thumbnails[$0] },
                session: session,
                onSetColor: { color in Task { await model.setColor(color) } },
                onOpen: { open(item.id) }
            )
            .id(item.id)
        } else {
            ContentUnavailableView {
                Label(
                    model.selection.isEmpty ? "Select a highlight" : "\(model.selection.count) highlights selected",
                    systemImage: "highlighter"
                )
            }
        }
    }

    private func open(_ id: String) {
        guard let item = model.items.first(where: { $0.id == id }) else { return }
        session.router.open(documentId: item.highlight.documentId, at: .highlight(id), using: openWindow)
    }
}

private extension HighlightListItem {
    /// Document, page and color as the row's accessibility value; `.combine` plus the label would otherwise hide them.
    var accessibilityDetail: String {
        var parts = [documentTitle]
        if let page = highlight.pageIndex { parts.append(String(localized: "p. \(page + 1)")) }
        parts.append(HighlightPalette.title(highlight.color))
        return parts.joined(separator: ", ")
    }
}

private struct HighlightBrowserRow: View {
    let item: HighlightListItem
    let thumbnail: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(HighlightPalette.color(item.highlight.color))
                .frame(width: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                content
                if !item.highlight.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(item.highlight.note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !item.tagNames.isEmpty {
                    Text(item.tagNames.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(item.documentTitle).lineLimit(1)
                    if let page = item.highlight.pageIndex {
                        Text("p. \(page + 1)")
                    }
                    Text(item.highlight.createdAt.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if item.highlight.anchorStatus == .orphaned {
                    Text("Couldn't locate in document")
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 60, alignment: .leading)
                .accessibilityLabel("Snapshot")
        } else if item.highlight.imagePath == nil {
            RichTextView(item.highlight.listExcerptMarkdown)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
