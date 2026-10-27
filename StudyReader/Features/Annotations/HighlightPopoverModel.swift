import Foundation
import Observation

/// State behind the highlight popover (SPEC F-06, F-09, F-10): the live highlight, its note and its tags.
/// Every action persists at once through `HighlightService`, the note editor and the tag field model.
@MainActor @Observable
final class HighlightPopoverModel {
    let highlightId: String
    let noteModel: NoteEditorModel
    let tagModel: TagFieldModel

    private(set) var highlight: Highlight?
    private(set) var isDeleted = false
    /// True once the live row has been read; a nil `highlight` after that means it was deleted elsewhere.
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let session: AppSession

    init(highlightId: String, session: AppSession) {
        self.highlightId = highlightId
        self.session = session
        self.noteModel = NoteEditorModel(target: .highlight(highlightId), environment: session.environment)
        self.tagModel = TagFieldModel(target: .highlight(highlightId), environment: session.environment)
    }

    /// True when the popover has nothing left to show: deleted here or removed elsewhere.
    var isGone: Bool { isDeleted || (hasLoaded && highlight == nil) }

    /// Loads the note, then runs the highlight and tag observations until the calling task is cancelled.
    func observe() async {
        await noteModel.load()
        async let tags: Void = tagModel.observe()
        async let live: Void = observeHighlight()
        _ = await (tags, live)
    }

    private func observeHighlight() async {
        do {
            for try await row in session.environment.highlightRepository.observeHighlight(id: highlightId) {
                highlight = row
                hasLoaded = true
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = String(localized: "The highlight couldn't be loaded.")
        }
    }

    /// Choosing the color it already has changes nothing, so it doesn't touch the row or the auto-highlight undo.
    func setColor(_ color: HighlightColor) async {
        guard highlight?.color != color else { return }
        do {
            try await session.environment.highlightService.setColor(id: highlightId, color: color)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "The color couldn't be changed.")
        }
    }

    func delete() async {
        do {
            try await session.environment.highlightService.delete(id: highlightId)
            isDeleted = true
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "The highlight couldn't be deleted.")
        }
    }

    /// Plain text for Copy: `editedText` when set, else `text`.
    var copyText: String {
        guard let highlight else { return "" }
        return highlight.editedText ?? highlight.text
    }

    /// For image highlights: the stored PNG.
    var imageURL: URL? {
        guard let path = highlight?.imagePath else { return nil }
        return session.environment.fileStore.url(forRelativePath: path)
    }
}
