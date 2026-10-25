import Foundation
import Observation

/// Logic for the sidebar Tags screen (SPEC F-10): the tag list with usage counts, rename, merge and delete.
/// Renames, merges and deletes never remove highlights or documents; only tag links change.
@MainActor @Observable
final class TagManagerModel {
    /// Every tag with its highlight and document counts, from `TagRepository.observeUsage()`.
    private(set) var usage: [TagUsage] = []

    /// User-facing message from the last failed rename, merge, delete or observation. Nil after a success.
    private(set) var errorMessage: String?

    @ObservationIgnored private let tagRepository: TagRepository

    init(environment: AppEnvironment) {
        self.tagRepository = environment.tagRepository
    }

    /// Runs the usage list until the calling task is cancelled (`.task {}` in the view).
    func observe() async {
        do {
            for try await observed in tagRepository.observeUsage() {
                usage = observed
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = Self.message(for: error)
        }
    }

    /// Renames the tag. A name used by another tag (any case) sets `errorMessage` to the duplicate-name text.
    func rename(tagId: String, to name: String) async {
        do {
            try await tagRepository.rename(id: tagId, to: name)
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Moves every link of `sourceId` to `targetId`, then deletes `sourceId`.
    func merge(sourceId: String, into targetId: String) async {
        do {
            try await tagRepository.merge(sourceId: sourceId, into: targetId)
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Deletes the tag and its links. The highlights and documents stay.
    func delete(tagId: String) async {
        do {
            try await tagRepository.delete(id: tagId)
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Clears the alert message once the user has seen it.
    func dismissError() {
        errorMessage = nil
    }

    private static func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? String(localized: "The tag couldn't be changed. Try again.")
    }
}
