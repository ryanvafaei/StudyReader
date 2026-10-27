import AppKit
import SwiftUI

/// Floating capsule shown when auto-highlight is off (SPEC F-06): five color dots, Note, Tag and Copy.
struct SelectionToolbarView: View {
    let model: ReaderModel
    let settings: AppSettings
    @State private var frameInWindow: CGRect = .zero
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 10) {
            ColorDotsView(settings: settings, selected: nil) { color in
                Task { await model.applyToolbarColor(color) }
            }
            Divider().frame(height: 16)
            Button {
                Task { await model.applyToolbarNoteOrTag(focus: .note) }
            } label: {
                Image(systemName: "note.text")
            }
            .help("Highlight and add a note")
            .accessibilityLabel("Add note")
            Button {
                Task { await model.applyToolbarNoteOrTag(focus: .tags) }
            } label: {
                Image(systemName: "tag")
            }
            .help("Highlight and add a tag")
            .accessibilityLabel("Add tag to selection")
            Button {
                model.engineActions.copySelection?()
                model.selectionToolbar = nil
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy the selection")
            .accessibilityLabel("Copy selection")

            Button("Dismiss") { model.selectionToolbar = nil }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .shadow(radius: 4, y: 1)
        .fixedSize()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frameInWindow = $0 }
        .onAppear(perform: startMonitor)
        .onDisappear(perform: stopMonitor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selection toolbar")
    }

    /// Closes the toolbar on a click outside it. The click still reaches the reader, so a new selection works.
    private func startMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            let height = event.window?.contentView?.frame.height ?? 0
            let point = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
            if !frameInWindow.insetBy(dx: -2, dy: -2).contains(point) {
                Task { @MainActor in model.selectionToolbar = nil }
            }
            return event
        }
    }

    private func stopMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
