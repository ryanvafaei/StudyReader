import SwiftUI

/// One review card: header, front, optional back, rating row. Keys go through the focused card only (ADR-0022).
struct ReviewCardView: View {
    let model: ReviewSessionModel
    let session: AppSession
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollView {
            if let content = model.content {
                VStack(alignment: .leading, spacing: 14) {
                    header(content)
                    Divider()
                    bodyView(content.front, identifier: "review-card-front")
                    if !content.needsReveal {
                        extras(content)
                    } else if model.isRevealed {
                        Divider()
                        if let back = content.back {
                            bodyView(back, identifier: "review-card-back")
                        }
                        if let source = content.source {
                            bodyView(source, identifier: "review-card-source")
                                .foregroundStyle(.secondary)
                        }
                        extras(content)
                    } else {
                        revealButton
                    }
                    ratingRow
                    if let message = model.errorMessage {
                        Text(LocalizedStringKey(message))
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("review-error")
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onChange(of: model.current?.id) { _, _ in isFocused = true }
        .onKeyPress(characters: CharacterSet(charactersIn: " 1234"), phases: .down) { press in
            guard let key = press.characters.first,
                  let action = model.action(forKey: key)
            else { return .ignored }
            Task { await model.perform(action) }
            return .handled
        }
    }

    private func header(_ content: ReviewCardContent) -> some View {
        HStack(spacing: 8) {
            Text(content.documentTitle)
                .font(.headline)
                .lineLimit(1)
                .accessibilityIdentifier("review-document-title")
            if let page = content.pageNumber {
                Text("p. \(page)")
                    .foregroundStyle(.secondary)
            }
            Circle()
                .fill(HighlightPalette.color(content.color))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(session.settings.label(for: content.color))
                .foregroundStyle(.secondary)
            Spacer()
            Text(model.progressText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityIdentifier("review-progress")
        }
    }

    @ViewBuilder
    private func bodyView(_ body: ReviewCardContent.Body, identifier: String) -> some View {
        switch body {
        case .markdown(let markdown):
            RichTextView(markdown)
                .font(.title3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .accessibilityIdentifier(identifier)
        case .image(let path):
            ReviewSnapshotView(session: session, relativePath: path)
                .accessibilityIdentifier(identifier)
        }
    }

    @ViewBuilder
    private func extras(_ content: ReviewCardContent) -> some View {
        if !content.note.isEmpty {
            NoteMarkdownView(content.note)
                .accessibilityIdentifier("review-card-note")
        }
        if !content.tagNames.isEmpty {
            HStack(spacing: 6) {
                ForEach(content.tagNames, id: \.self) { name in
                    Text("#\(name)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            .accessibilityIdentifier("review-card-tags")
        }
    }

    private var revealButton: some View {
        Button {
            model.reveal()
        } label: {
            HStack {
                Text("Show Answer")
                Text("Space")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(Text("Show Answer"))
        .accessibilityIdentifier("review-reveal")
    }

    private var ratingRow: some View {
        HStack(spacing: 10) {
            ForEach(model.ratingButtons) { button in
                Button {
                    Task { await model.rate(button.rating) }
                } label: {
                    VStack(spacing: 2) {
                        Text(button.title)
                        Text(String(button.key))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 64)
                }
                .disabled(!model.canRate)
                .accessibilityLabel(Text(button.title))
                .accessibilityIdentifier(Self.identifier(for: button.rating))
            }
        }
        .padding(.top, 6)
    }

    private static func identifier(for rating: ReviewRating) -> String {
        switch rating {
        case .again: "review-rate-again"
        case .hard: "review-rate-hard"
        case .good: "review-rate-good"
        case .easy: "review-rate-easy"
        }
    }
}

/// The PNG of an image highlight. Loaded once per path, never in `body`.
private struct ReviewSnapshotView: View {
    let session: AppSession
    let relativePath: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 360)
                    .accessibilityLabel(Text("Snapshot"))
            } else {
                ProgressView()
            }
        }
        .task(id: relativePath) {
            guard let url = session.environment.fileStore.url(forRelativePath: relativePath) else { return }
            image = NSImage(contentsOf: url)
        }
    }
}
