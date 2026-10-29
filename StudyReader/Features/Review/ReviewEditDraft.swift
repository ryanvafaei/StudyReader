import Foundation
import Observation

/// Draft for "Edit highlight" (SPEC F-18). Starts with editedText ?? text; save returns what to store.
@MainActor @Observable
final class ReviewEditDraft {
    var text: String

    @ObservationIgnored private let original: String
    @ObservationIgnored private let startingText: String

    init(highlight: Highlight) {
        let start = highlight.editedText ?? highlight.text
        self.text = start
        self.startingText = start
        self.original = highlight.text
    }

    /// The text differs from the starting text.
    var isChanged: Bool {
        text != startingText
    }

    /// nil when the text is whitespace-only or equals the highlight's original text (the edit is removed), else the text as typed.
    var valueToStore: String? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text == original {
            return nil
        }
        return text
    }
}
