import SwiftUI

/// Grouped global search results (SPEC F-12) that replace the detail column while a query is active.
/// Holds no logic: `SearchModel` runs the search and maps hits to reader locations.
struct SearchResultsView: View {
    let session: AppSession
    @Environment(\.openWindow) private var openWindow

    private var search: SearchModel { session.search }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            content
        }
        .navigationTitle("Search")
        .task { await search.observeTags() }
        .task { await search.observeCategories() }
    }

    // MARK: - Filters

    private var filterBar: some View {
        @Bindable var search = search
        return HStack(spacing: 12) {
            Picker("Tag", selection: $search.filters.tagId) {
                Text("Any Tag").tag(Optional<String>.none)
                ForEach(search.tags) { tag in
                    Text(tag.name).tag(Optional(tag.id))
                }
            }
            .accessibilityLabel("Filter by tag")

            Picker("Category", selection: $search.filters.categoryId) {
                Text("Any Category").tag(Optional<String>.none)
                ForEach(search.categories) { category in
                    Text(category.name).tag(Optional(category.id))
                }
            }
            .accessibilityLabel("Filter by category")

            Picker("Type", selection: $search.filters.fileType) {
                Text("Any Type").tag(Optional<FileType>.none)
                Text("PDF").tag(Optional(FileType.pdf))
                Text("Markdown").tag(Optional(FileType.markdown))
            }
            .accessibilityLabel("Filter by file type")

            Button("Clear") {
                search.filters = SearchFilters()
            }
            .disabled(search.filters == SearchFilters())
            .accessibilityLabel("Clear search filters")

            Spacer()
            if search.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Searching")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Results

    @ViewBuilder
    private var content: some View {
        if let message = search.errorMessage {
            ContentUnavailableView("Search failed", systemImage: "exclamationmark.triangle", description: Text(message))
        } else if search.results.isEmpty {
            if search.isSearching {
                Color.clear
            } else {
                ContentUnavailableView {
                    Label("No results for \"\(search.query)\"", systemImage: "magnifyingglass")
                }
            }
        } else {
            List {
                if !search.results.documents.isEmpty {
                    Section("Documents (\(search.results.documents.count))") {
                        ForEach(search.results.documents) { hit in
                            Button { open(hit) } label: { DocumentHitRow(hit: hit) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("search-hit-document")
                        }
                    }
                }
                if !search.results.highlights.isEmpty {
                    Section("Highlights (\(search.results.highlights.count))") {
                        ForEach(search.results.highlights) { hit in
                            Button { open(hit) } label: { HighlightHitRow(hit: hit) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("search-hit-highlight")
                        }
                    }
                }
                if !search.results.notes.isEmpty {
                    Section("Notes (\(search.results.notes.count))") {
                        ForEach(search.results.notes) { hit in
                            Button { open(hit) } label: { NoteHitRow(hit: hit) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("search-hit-note")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func open(_ hit: DocumentHit) {
        session.router.open(
            documentId: hit.documentId,
            at: SearchModel.location(for: hit, query: search.query),
            using: openWindow
        )
    }

    private func open(_ hit: HighlightHit) {
        session.router.open(documentId: hit.documentId, at: SearchModel.location(for: hit), using: openWindow)
    }

    private func open(_ hit: NoteHit) {
        session.router.open(documentId: hit.documentId, at: SearchModel.location(for: hit), using: openWindow)
    }
}

private struct DocumentHitRow: View {
    let hit: DocumentHit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(hit.title)
                    .font(.headline)
                    .lineLimit(1)
                if let place {
                    Text(place)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(attributedSnippet(hit.snippet))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "p. N" for a PDF page, "Section N" for Markdown. Title and author hits have no place.
    private var place: String? {
        guard hit.field == .text, let index = hit.unitIndex else { return nil }
        return hit.fileType == .markdown
            ? String(localized: "Section \(index + 1)")
            : String(localized: "p. \(index + 1)")
    }
}

private struct HighlightHitRow: View {
    let hit: HighlightHit

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(hit.documentTitle)
                        .font(.headline)
                        .lineLimit(1)
                    if let pageIndex = hit.pageIndex {
                        Text("p. \(pageIndex + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(attributedSnippet(hit.snippet))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct NoteHitRow: View {
    let hit: NoteHit

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: hit.kind == .highlightNote ? "highlighter" : "note.text")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.documentTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(attributedSnippet(hit.snippet))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
