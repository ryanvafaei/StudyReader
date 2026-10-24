import SwiftUI

/// Main window content: sidebar of sections and a placeholder detail pane.
struct RootView: View {
    @State private var model: RootModel

    init(environment: AppEnvironment) {
        _model = State(initialValue: RootModel(environment: environment))
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $model.selection) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            if let item = model.selection {
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
    }
}
