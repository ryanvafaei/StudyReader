import SwiftUI

/// Chips for the assigned tags, an "Add tag" field and autocomplete suggestions (SPEC F-10).
/// Hosts pass a `TagFieldModel` for their target. The view holds no state of its own.
struct TagFieldView: View {
    @Bindable var model: TagFieldModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.hasLoadedAssignedTags && model.tags.isEmpty {
                Text("No tags yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if model.tags.isEmpty {
                // Not loaded yet: keep the line's height so nothing moves when the tags arrive.
                Text(" ")
                    .font(.callout)
                    .accessibilityHidden(true)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(model.tags) { tag in
                        TagChip(name: tag.name) {
                            Task { await model.remove(tagId: tag.id) }
                        }
                    }
                }
            }

            TextField("Add tag", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(Text("Add tag"))
                .onSubmit {
                    Task { await model.submit() }
                }
                .onKeyPress(.downArrow) {
                    model.moveHighlight(by: 1)
                    return model.suggestions.isEmpty ? .ignored : .handled
                }
                .onKeyPress(.upArrow) {
                    model.moveHighlight(by: -1)
                    return model.suggestions.isEmpty ? .ignored : .handled
                }

            if !model.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { index, tag in
                        Button {
                            Task { await model.add(name: tag.name) }
                        } label: {
                            Text("#\(tag.name)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    model.highlightedSuggestion == index
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 5)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Add tag \(tag.name)"))
                    }
                }
            }

            if let message = model.errorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .task {
            await model.observe()
        }
    }
}

/// A tag shown as "#name" with a remove button.
private struct TagChip: View {
    let name: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("#\(name)")
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove tag \(name)"))
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
    }
}

/// Places subviews left to right and wraps to a new row when the width runs out.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(maxWidth: proposal.width ?? .greatestFiniteMagnitude, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let origins = arrange(maxWidth: bounds.width, subviews: subviews).origins
        for (index, origin) in origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return (origins, CGSize(width: width, height: y + rowHeight))
    }
}
