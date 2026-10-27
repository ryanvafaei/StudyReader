import AppKit
import SwiftUI

/// Content of one reader window (one document tab, ADR-0017). Joins the main window's tab group on open. A nil
/// document ID (state restoration without a value) shows only "No document".
struct ReaderWindowRoot: View {
    let documentId: String?
    let launchModel: AppLaunchModel
    /// The hosting window, so a new location for an already open document can bring its tab forward.
    @State private var window: NSWindow?

    var body: some View {
        content
            .background(WindowAccessor { hostWindow in
                if documentId == nil {
                    ReaderTabbing.discardEmptyWindow(hostWindow)
                } else {
                    ReaderTabbing.joinMainTabGroup(hostWindow)
                }
                // A @State write during the layout pass re-enters SwiftUI's layout (T52h), so it waits a turn.
                Task { @MainActor in
                    window = hostWindow
                }
            })
    }

    @ViewBuilder
    private var content: some View {
        if let documentId {
            ReaderWindowView(documentId: documentId, launchModel: launchModel) {
                window?.makeKeyAndOrderFront(nil)
            }
        } else {
            ContentUnavailableView("No document", systemImage: "doc")
        }
    }
}

/// Waits for the library to open, then shows the reader for one document.
struct ReaderWindowView: View {
    let documentId: String
    let launchModel: AppLaunchModel
    /// Called when the router queues a new location for this document while the tab is open.
    let onLocationQueued: (@MainActor () -> Void)?

    init(documentId: String, launchModel: AppLaunchModel, onLocationQueued: (@MainActor () -> Void)? = nil) {
        self.documentId = documentId
        self.launchModel = launchModel
        self.onLocationQueued = onLocationQueued
    }

    var body: some View {
        if let session = launchModel.session {
            ReaderTabContent(documentId: documentId, session: session, onLocationQueued: onLocationQueued)
        } else {
            ProgressView("Opening library…")
        }
    }
}

/// The tab itself: loading and error states, the content slot, the toolbar, the side panel and the banner.
private struct ReaderTabContent: View {
    let documentId: String
    let session: AppSession
    let onLocationQueued: (@MainActor () -> Void)?
    @State private var model: ReaderModel
    @State private var windowState = ReaderWindowState()

    init(documentId: String, session: AppSession, onLocationQueued: (@MainActor () -> Void)?) {
        self.documentId = documentId
        self.session = session
        self.onLocationQueued = onLocationQueued
        _model = State(initialValue: ReaderModel(documentId: documentId, session: session))
    }

    var body: some View {
        content
            .navigationTitle(model.document?.title ?? "")
            .navigationSubtitle(model.categoryName ?? "")
            .toolbar { toolbarItems }
            .inspector(isPresented: inspectorBinding) {
                ReaderSidePanel(model: model)
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
            }
            .overlay(alignment: .bottom) { banner }
            .sheet(isPresented: Bindable(windowState).isMetadataSheetPresented) {
                MetadataSheet(
                    session: session,
                    request: MetadataRequest(
                        documentId: documentId,
                        currentPageIndex: model.engineActions.currentPageIndex?()
                    )
                )
            }
            .focusedSceneValue(\.readerActions, ReaderActions(model: model, windowState: windowState))
            .task { await model.load() }
            .task { await model.observeHighlights() }
            .task { await model.observeMetadata() }
            .task(id: model.transientMessage) { await hideBannerAfterDelay() }
            .onChange(of: session.router.pendingLocations[documentId]) { _, location in
                model.receiveRouterLocation()
                if location != nil {
                    onLocationQueued?()
                }
            }
            .onDisappear {
                // Closing the tab closes its window; keep the latest reading position.
                Task { await model.flushPosition() }
            }
    }

    /// The inspector shows only for a loaded document; a failed reader has nothing to list.
    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { model.isDocumentAvailable && model.isRightPanelVisible },
            set: { model.isRightPanelVisible = $0 }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .controlSize(.large)
        case .failed(let message):
            ContentUnavailableView(message, systemImage: "exclamationmark.triangle")
        case .ready:
            ReaderContentSlot(model: model)
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if model.isDocumentAvailable {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Highlight color", selection: Bindable(session.settings).currentColor) {
                        ForEach(HighlightColor.allCases, id: \.self) { color in
                            Label {
                                Text(session.settings.label(for: color))
                            } icon: {
                                Image(nsImage: HighlightPalette.swatchImage(color))
                            }
                            .tag(color)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(HighlightPalette.color(session.settings.currentColor))
                }
                .help("Highlight color for new highlights")
                .accessibilityLabel("Highlight color")
            }
        }

        if model.engineActions.findInDocument != nil {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.engineActions.findInDocument?()
                } label: {
                    Label("Find in Document", systemImage: "magnifyingglass")
                }
                .help("Find in document")
                .accessibilityLabel("Find in document")
            }
        }

        if model.engineActions.startSnapshot != nil {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.engineActions.startSnapshot?()
                } label: {
                    Label("Snapshot", systemImage: "camera.viewfinder")
                }
                .help("Take a snapshot of the page or section")
                .accessibilityLabel("Snapshot")
            }
        }

        if model.isDocumentAvailable {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.toggleRightPanel(tab: model.rightPanelTab)
                } label: {
                    Label("Highlights panel", systemImage: "sidebar.right")
                }
                .help("Show or hide the Highlights and Notes panel")
                .accessibilityLabel("Show or hide the Highlights and Notes panel")
            }
        }
    }

    @ViewBuilder
    private var banner: some View {
        if let message = model.transientMessage {
            Text(message)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: .capsule)
                .padding(.bottom, 16)
                .accessibilityAddTraits(.isStaticText)
        }
    }

    /// Hides the banner after 3 seconds. Restarts when the message changes; cancelled when the view goes away.
    private func hideBannerAfterDelay() async {
        guard model.transientMessage != nil else { return }
        do {
            try await Task.sleep(for: .seconds(3))
        } catch {
            return
        }
        model.clearTransientMessage()
    }
}

/// Engine slot. T55 replaces the Markdown placeholder.
struct ReaderContentSlot: View {
    let model: ReaderModel

    var body: some View {
        switch model.document?.fileType {
        case .pdf:
            PDFReaderView(model: model)
        case .markdown:
            Text("Markdown reader arrives in T55")
                .foregroundStyle(.secondary)
        case nil:
            ProgressView()
        }
    }
}

/// Right column with the Highlights and Notes tabs. The content arrives with T63.
private struct ReaderSidePanel: View {
    @Bindable var model: ReaderModel

    var body: some View {
        VStack(spacing: 12) {
            Picker("Panel", selection: $model.rightPanelTab) {
                Text("Highlights").tag(ReaderPanelTab.highlights)
                Text("Notes").tag(ReaderPanelTab.notes)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Panel")

            Spacer()
            Text("Panel content arrives in T63")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }
}
