import SwiftUI

/// The five highlight color dots shared by the popover and the selection toolbar. Each is a Tab-reachable button
/// with the color's label as tooltip and "Yellow, Key concept" as accessibility label.
struct ColorDotsView: View {
    let settings: AppSettings
    let selected: HighlightColor?
    let onPick: (HighlightColor) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button {
                    onPick(color)
                } label: {
                    Circle()
                        .fill(HighlightPalette.color(color))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
                        .overlay {
                            if selected == color {
                                Circle().strokeBorder(Color.primary, lineWidth: 2).padding(-3)
                            }
                        }
                        .padding(3)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(settings.label(for: color))
                .accessibilityLabel(Text("\(HighlightPalette.title(color)), \(settings.label(for: color))"))
                .accessibilityAddTraits(selected == color ? .isSelected : [])
            }
        }
    }
}
