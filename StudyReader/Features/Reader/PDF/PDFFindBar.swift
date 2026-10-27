import SwiftUI

/// The find bar at the top of the PDF view: a text field, "n of m", previous and next buttons and Done. Return steps
/// to the next match, Shift-Return to the previous one, Escape closes. Typing searches after a short pause, because a
/// PDFKit search of a long document takes a moment.
struct PDFFindBar: View {
    static let searchDelay: Duration = .milliseconds(250)

    let find: PDFFindController
    let sleeper: any Sleeper
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in document", text: Bindable(find).query)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, maxWidth: 280)
                .focused($isFieldFocused)
                .accessibilityLabel("Find in document")
                .onSubmit { find.next() }
                .onKeyPress(.return, phases: .down) { press in
                    // Plain Return is left to onSubmit; only Shift-Return needs the key event.
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    find.previous()
                    return .handled
                }
            Text(status)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .leading)
                .accessibilityLabel("Match count")
            Button {
                find.previous()
            } label: {
                Label("Previous match", systemImage: "chevron.up")
                    .labelStyle(.iconOnly)
            }
            .disabled(find.matchCount == 0)
            .help("Previous match (⇧↩)")
            Button {
                find.next()
            } label: {
                Label("Next match", systemImage: "chevron.down")
                    .labelStyle(.iconOnly)
            }
            .disabled(find.matchCount == 0)
            .help("Next match (↩)")
            Button("Done") {
                find.close()
            }
            .accessibilityLabel("Close find bar")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .onExitCommand {
            find.close()
        }
        .onChange(of: find.focusRequest, initial: true) {
            isFieldFocused = true
        }
        .task(id: find.query) {
            try? await sleeper.sleep(for: Self.searchDelay)
            guard !Task.isCancelled else { return }
            find.search()
        }
    }

    /// "3 of 12", "No matches", or nothing for an empty query.
    private var status: String {
        if let index = find.currentIndex {
            return String(localized: "\(index + 1) of \(find.matchCount)")
        }
        return find.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : String(localized: "No matches")
    }
}
