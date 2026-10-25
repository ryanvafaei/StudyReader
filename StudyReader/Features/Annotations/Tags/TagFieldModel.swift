import Foundation
import Observation

/// The tagged item: a highlight or a document (SPEC F-10). The tag field and the tag manager share it.
enum TagTarget: Equatable, Sendable {
    case highlight(String)
    case document(String)
}

/// Logic for the tag field (SPEC F-10): assigned tags, autocomplete from existing tags, and create-on-type.
/// Typing a name that matches no tag creates it; a name that matches an existing tag (any case) reuses it.
@MainActor @Observable
final class TagFieldModel {
    nonisolated static let suggestionLimit = 8

    let target: TagTarget

    /// Tags assigned to the target, in name order.
    private(set) var tags: [LibraryTag] = []

    /// The text in the "Add tag" field. Changing it recomputes `suggestions`.
    var query: String = "" {
        didSet { refreshSuggestions() }
    }

    /// Up to `suggestionLimit` existing tags that start with the query and aren't assigned yet, in name order.
    private(set) var suggestions: [LibraryTag] = []

    /// Index into `suggestions` picked with the arrow keys, or nil. Return adds this suggestion when set.
    private(set) var highlightedSuggestion: Int?

    /// User-facing message from the last failed add, remove or observation. Nil after a successful change.
    private(set) var errorMessage: String?

    @ObservationIgnored private let tagRepository: TagRepository
    @ObservationIgnored private let now: any Now

    /// Every tag in the library, from `TagRepository.observeAll()`. Source for `suggestions`.
    @ObservationIgnored private var allTags: [LibraryTag] = [] {
        didSet { refreshSuggestions() }
    }

    init(target: TagTarget, environment: AppEnvironment) {
        self.target = target
        self.tagRepository = environment.tagRepository
        self.now = environment.now
    }

    /// Runs the assigned-tag list and the all-tag list until the calling task is cancelled.
    func observe() async {
        async let assigned: Void = observeAssigned()
        async let everything: Void = observeAll()
        _ = await (assigned, everything)
    }

    /// Return in the field: adds the highlighted suggestion, else the typed query. A blank query does nothing.
    func submit() async {
        if let index = highlightedSuggestion, suggestions.indices.contains(index) {
            await add(name: suggestions[index].name)
        } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await add(name: query)
        }
    }

    /// Moves the highlight through `suggestions` by `step` (wraps around). Does nothing when there are none.
    func moveHighlight(by step: Int) {
        let count = suggestions.count
        guard count > 0 else {
            highlightedSuggestion = nil
            return
        }
        let current = highlightedSuggestion ?? (step > 0 ? -1 : count)
        highlightedSuggestion = ((current + step) % count + count) % count
    }

    /// Finds or creates the tag named `name`, then assigns it to the target. Clears `query` on success.
    /// An invalid name leaves `query` as typed and sets `errorMessage`.
    func add(name: String) async {
        do {
            let tag = try await tagRepository.findOrCreate(name: name, at: now())
            let current = try await assignedTags().map(\.id)
            guard !current.contains(tag.id) else {
                query = ""
                errorMessage = nil
                return
            }
            try await setAssignedTags(current + [tag.id])
            query = ""
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Removes the tag from the target. The tag itself stays in the library.
    func remove(tagId: String) async {
        do {
            let remaining = try await assignedTags().map(\.id).filter { $0 != tagId }
            try await setAssignedTags(remaining)
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Pure: existing tags whose name starts with the query, ignoring case and a leading "#". Assigned tags
    /// are excluded, the order of `tags` is kept, and at most `limit` are returned. An empty query gives [].
    nonisolated static func suggestions(
        for query: String,
        in tags: [LibraryTag],
        excluding assignedIds: Set<String>,
        limit: Int = suggestionLimit
    ) -> [LibraryTag] {
        var prefix = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if prefix.hasPrefix("#") {
            prefix.removeFirst()
        }
        prefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !prefix.isEmpty else { return [] }
        return tags
            .filter { !assignedIds.contains($0.id) && $0.name.lowercased().hasPrefix(prefix) }
            .prefix(limit)
            .map { $0 }
    }

    private func refreshSuggestions() {
        suggestions = Self.suggestions(
            for: query,
            in: allTags,
            excluding: Set(tags.map(\.id))
        )
        highlightedSuggestion = nil
    }

    private func observeAssigned() async {
        do {
            switch target {
            case .highlight(let highlightId):
                for try await observed in tagRepository.observeTags(forHighlight: highlightId) {
                    tags = observed
                    refreshSuggestions()
                }
            case .document(let documentId):
                for try await observed in tagRepository.observeTags(forDocument: documentId) {
                    tags = observed
                    refreshSuggestions()
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = Self.message(for: error)
        }
    }

    private func observeAll() async {
        do {
            for try await observed in tagRepository.observeAll() {
                allTags = observed
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = Self.message(for: error)
        }
    }

    /// Reads the current assignments from the repository, so a change never works from a stale copy.
    private func assignedTags() async throws -> [LibraryTag] {
        switch target {
        case .highlight(let highlightId):
            try await tagRepository.tags(forHighlight: highlightId)
        case .document(let documentId):
            try await tagRepository.tags(forDocument: documentId)
        }
    }

    private func setAssignedTags(_ tagIds: [String]) async throws {
        switch target {
        case .highlight(let highlightId):
            try await tagRepository.setTags(tagIds, forHighlight: highlightId)
        case .document(let documentId):
            try await tagRepository.setTags(tagIds, forDocument: documentId)
        }
    }

    private static func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? String(localized: "The tags couldn't be updated. Try again.")
    }
}
