import SwiftUI
import UniformTypeIdentifiers

/// Main window content: sidebar of sections and a placeholder detail pane.
/// Also the window's import entry points: drops, File > Import (⌘O) and Dock or Open With URLs (SPEC F-02).
struct RootView: View {
    @State private var model: RootModel
    @State private var isShowingImporter = false
    @State private var isDropTargeted = false
    @FocusState private var searchFieldFocused: Bool
    let session: AppSession

    init(session: AppSession) {
        self.session = session
        _model = State(initialValue: RootModel(environment: session.environment))
    }

    var body: some View {
        @Bindable var search = session.search
        return NavigationSplitView {
            List(SidebarItem.allCases, selection: $model.selection) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item)
                    .badge(badgeCount(for: item))
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            if search.isActive {
                SearchResultsView(session: session)
            } else if model.selection == .library {
                LibraryView(session: session, onImport: { isShowingImporter = true })
            } else if model.selection == .tags {
                TagManagerView(session: session)
            } else if model.selection == .categories {
                CategoryManagerView(session: session)
            } else if model.selection == .highlights {
                // LibraryView (with its hidden Return/Escape buttons) is not in the hierarchy here (T69).
                HighlightsBrowserView(session: session)
            } else if model.selection == .review {
                // LibraryView is not in the hierarchy here, so its Return/Escape buttons are gone (T109).
                ReviewSectionView(session: session)
            } else if model.selection == .themedReviews {
                // LibraryView is not in the hierarchy here: Return runs the selected review, Escape does nothing (T124).
                ThemedReviewsView(session: session)
            } else if let item = model.selection {
                ContentUnavailableView(
                    item.title,
                    systemImage: item.systemImage,
                    description: Text("This section isn't built yet.")
                )
            } else {
                ContentUnavailableView("Select a section", systemImage: "sidebar.left")
            }
        }
        .searchable(text: $search.query, placement: .toolbar, prompt: "Search library")
        .searchFocused($searchFieldFocused)
        // `AppSession.isSearchFocused` mirrors the field's focus: commands set it, LibraryView reads it.
        .onChange(of: searchFieldFocused) { _, focused in
            session.isSearchFocused = focused
        }
        .onChange(of: session.isSearchFocused) { _, focused in
            if searchFieldFocused != focused { searchFieldFocused = focused }
        }
        .onSubmit(of: .search) {
            Task { await session.search.searchNow() }
        }
        .frame(minWidth: MainWindowLayout.minWidth, minHeight: MainWindowLayout.minHeight)
        .overlay {
            if isDropTargeted {
                ImportDropOverlay()
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            session.importCoordinator.importURLs(urls)
            return true
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: Self.importerTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                session.importCoordinator.importURLs(urls)
            }
        }
        .importPrompts(session.importCoordinator)
        .focusedSceneValue(\.searchSession, session)
        .focusedSceneValue(\.importActions, ImportActions(importFiles: { isShowingImporter = true }))
        // The library window is the first tab of the group that reader windows join (ADR-0017, T52).
        .background(WindowAccessor { ReaderTabbing.configureMain($0) })
        .task(id: session.settings.dailyLimits) {
            await session.reviewBadge.observe()
        }
        .task {
            await session.reviewBadge.observeThemed()
        }
        .task {
            // Dock and Open With URLs that arrived before this window existed are handed over here.
            ExternalURLRouter.shared.attach { urls in
                session.importCoordinator.importURLs(urls)
            }
        }
    }

    private func badgeCount(for item: SidebarItem) -> Int {
        switch item {
        case .review: session.reviewBadge.dailyDueCount
        case .themedReviews: session.reviewBadge.themedDueCount
        default: 0
        }
    }

    /// File types the importer offers: PDF, Markdown and folders (SPEC F-02). Markdown types are optional because
    /// the system may not declare them.
    private static var importerTypes: [UTType] {
        var types: [UTType] = [.pdf, .folder]
        if let markdown = UTType("net.daringfireball.markdown") {
            types.append(markdown)
        }
        if let md = UTType(filenameExtension: "md") {
            types.append(md)
        }
        return types
    }
}
