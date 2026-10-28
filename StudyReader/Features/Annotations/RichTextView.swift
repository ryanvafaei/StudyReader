import SwiftUI

/// Renders a stored rich-text string (the F-07 subset). Shows the raw string when it can't be parsed.
struct RichTextView: View {
    private let markdown: String

    init(_ markdown: String) {
        self.markdown = markdown
    }

    var body: some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: markdown,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attributed)
            } else {
                Text(verbatim: markdown)
            }
        }
        .studyReaderLinkPolicy()
    }
}
