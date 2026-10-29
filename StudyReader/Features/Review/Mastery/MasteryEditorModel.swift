import Foundation
import Observation

/// State and logic of the Mastery editor sheet (SPEC F-16, ADR-0021). Cloze ranges are UTF-16 offsets into
/// `sourceText`, the same offsets `NSTextView.selectedRange()` reports.
@MainActor @Observable
final class MasteryEditorModel {
    private(set) var sourceText = ""
    private(set) var isImageHighlight = false
    /// Relative path of the snapshot PNG of an image highlight.
    private(set) var imagePath: String?
    private(set) var drafts: [MasteryDraft] = []
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    /// The current selection in the cloze text view (UTF-16). nil or empty = none.
    var selection: ClozeRange?
    /// The draft the editor shows.
    var selectedDraftId: String?

    @ObservationIgnored private let highlightId: String
    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private var loadedDrafts: [MasteryDraft] = []

    init(highlightId: String, environment: AppEnvironment) {
        self.highlightId = highlightId
        self.environment = environment
    }

    func load() async {
        do {
            let text = try await environment.masteryService.clozeSourceText(highlightId: highlightId)
            let loaded = try await environment.masteryService.drafts(highlightId: highlightId)
            let highlight = try await environment.highlightRepository.fetch(id: highlightId)
            sourceText = text
            isImageHighlight = highlight?.kind == .image
            imagePath = highlight?.imagePath
            drafts = loaded
            loadedDrafts = loaded
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
    }

    var canAddCloze: Bool {
        !isImageHighlight && (selection?.length ?? 0) > 0
    }

    /// The draft selected in the list, when it is a cloze.
    var selectedClozeDraft: MasteryDraft? {
        guard let draft = selectedDraft, case .cloze = draft.kind else { return nil }
        return draft
    }

    var selectedDraft: MasteryDraft? {
        drafts.first { $0.id == selectedDraftId }
    }

    /// Ranges of the selected cloze draft, for tinting.
    var selectedClozeRanges: [ClozeRange] {
        guard case .cloze(let ranges)? = selectedClozeDraft?.kind else { return [] }
        return ranges
    }

    var canAddToSelectedCloze: Bool {
        canAddCloze && selectedClozeDraft != nil
    }

    func addCloze() {
        guard canAddCloze, let selection else { return }
        let ranges = ClozeText.normalized([selection.pair], in: sourceText)
        guard !ranges.isEmpty else { return }
        let draft = MasteryDraft(id: UUID().uuidString, isSaved: false, kind: .cloze(ranges: ranges))
        drafts.append(draft)
        selectedDraftId = draft.id
        self.selection = nil
        errorMessage = nil
    }

    func addSelectionToSelectedCloze() {
        guard canAddToSelectedCloze, let selection, let index = selectedIndex,
              case .cloze(let ranges) = drafts[index].kind else { return }
        let merged = ClozeText.normalized((ranges + [selection]).map(\.pair), in: sourceText)
        drafts[index].kind = .cloze(ranges: merged)
        self.selection = nil
        errorMessage = nil
    }

    func addQuestion() {
        let draft = MasteryDraft(id: UUID().uuidString, isSaved: false, kind: .qa(question: "", answer: sourceText))
        drafts.append(draft)
        selectedDraftId = draft.id
        errorMessage = nil
    }

    func updateQuestion(_ text: String, for draftId: String) {
        guard let index = drafts.firstIndex(where: { $0.id == draftId }),
              case .qa(_, let answer) = drafts[index].kind else { return }
        drafts[index].kind = .qa(question: text, answer: answer)
    }

    func updateAnswer(_ text: String, for draftId: String) {
        guard let index = drafts.firstIndex(where: { $0.id == draftId }),
              case .qa(let question, _) = drafts[index].kind else { return }
        drafts[index].kind = .qa(question: question, answer: text)
    }

    func remove(_ draftId: String) {
        drafts.removeAll { $0.id == draftId }
        if selectedDraftId == draftId {
            selectedDraftId = nil
        }
    }

    func save() async -> Bool {
        do {
            try await environment.masteryService.save(drafts, highlightId: highlightId)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    var isDirty: Bool {
        drafts != loadedDrafts
    }

    private var selectedIndex: Int? {
        drafts.firstIndex { $0.id == selectedDraftId }
    }
}
