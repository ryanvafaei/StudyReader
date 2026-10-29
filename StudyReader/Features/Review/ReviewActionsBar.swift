import SwiftUI

/// The row of card actions under the rating buttons (SPEC F-18). Persisting actions go through the model; the
/// note and edit editors are hosted by `ReviewCardView`. No key handling here (ADR-0022).
struct ReviewActionsBar: View {
    @Bindable var model: ReviewSessionModel
    let session: AppSession
    let isNoteOpen: Bool
    let isEditOpen: Bool
    let onToggleNote: () -> Void
    let onToggleEdit: () -> Void
    let onFrequency: (ReviewFrequency?) -> Void
    let onSkip: () -> Void

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let item = model.current, let content = model.content {
            HStack(spacing: 8) {
                Button {
                    onToggleNote()
                } label: {
                    Label("Note", systemImage: isNoteOpen ? "note.text.badge.plus" : "note.text")
                }
                .disabled(model.isBusy)
                .accessibilityLabel(Text("Note"))
                .accessibilityIdentifier("review-action-note")

                Button {
                    onToggleEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .disabled(model.isBusy || item.highlight.kind == .image)
                .accessibilityLabel(Text("Edit"))
                .accessibilityIdentifier("review-action-edit")

                if content.isEdited {
                    Toggle(isOn: $model.showOriginal) {
                        Text("Show Original")
                    }
                    .toggleStyle(.button)
                    .accessibilityLabel(Text("Show Original"))
                    .accessibilityIdentifier("review-show-original")
                }

                frequencyMenu(item)

                Button {
                    session.router.open(
                        documentId: item.highlight.documentId,
                        at: .highlight(item.highlight.id),
                        using: openWindow
                    )
                } label: {
                    Label("Open in Document", systemImage: "doc.text")
                }
                .disabled(model.isBusy)
                .accessibilityLabel(Text("Open in Document"))
                .accessibilityIdentifier("review-action-open")

                Button {
                    onSkip()
                } label: {
                    Label("Skip", systemImage: "forward")
                }
                .disabled(model.isBusy)
                .accessibilityLabel(Text("Skip"))
                .accessibilityIdentifier("review-action-skip")
            }
            .buttonStyle(.bordered)
        }
    }

    private func frequencyMenu(_ item: ReviewCardItem) -> some View {
        let current = item.card.frequencyOverride
        return Menu {
            choice(
                Text("Category default (\(Self.name(item.categoryFrequency)))"),
                isOn: current == nil,
                value: nil
            )
            ForEach(ReviewFrequency.allCases, id: \.self) { frequency in
                choice(Text(Self.name(frequency)), isOn: current == frequency, value: frequency)
            }
        } label: {
            Label("Frequency", systemImage: "gauge.with.dots.needle.bottom.50percent")
        }
        .menuIndicator(.visible)
        .fixedSize()
        .disabled(model.isBusy)
        .accessibilityLabel(Text("Frequency"))
        .accessibilityIdentifier("review-action-frequency")
    }

    private func choice(_ title: Text, isOn: Bool, value: ReviewFrequency?) -> some View {
        Button {
            onFrequency(value)
        } label: {
            if isOn {
                Label { title } icon: { Image(systemName: "checkmark") }
            } else {
                title
            }
        }
    }

    private static func name(_ frequency: ReviewFrequency) -> String {
        switch frequency {
        case .off: String(localized: "Off")
        case .low: String(localized: "Low")
        case .normal: String(localized: "Normal")
        case .high: String(localized: "High")
        }
    }
}
