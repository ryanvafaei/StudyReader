import SwiftUI
import UniformTypeIdentifiers

/// Main window content: sidebar of sections and a placeholder detail pane.
/// Also the window's import entry points: drops, File > Import (⌘O) and Dock or Open With URLs (SPEC F-02).
struct RootView: View {
    @State private var model: RootModel
    @State private var isShowingImporter = false
    @State private var isDropTargeted = false
    let session: AppSession

    init(session: AppSession) {
        self.session = session
        _model = State(initialValue: RootModel(environment: session.environment))
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $model.selection) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            if model.selection == .library {
                LibraryView(session: session, onImport: { isShowingImporter = true })
            } else if model.selection == .tags {
                TagManagerView(session: session)
            } else if model.selection == .categories {
                CategoryManagerView(session: session)
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
        .focusedSceneValue(\.importActions, ImportActions(importFiles: { isShowingImporter = true }))
        .task {
            // Dock and Open With URLs that arrived before this window existed are handed over here.
            ExternalURLRouter.shared.attach { urls in
                session.importCoordinator.importURLs(urls)
            }
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
