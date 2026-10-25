import Foundation
import Observation

/// Logic for the sidebar Categories screen (SPEC F-01, F-11): every category with its document count, and
/// add, rename and delete for custom categories. Built-in categories refuse rename and delete with an error.
@MainActor @Observable
final class CategoryManagerModel {
    /// Categories with their document counts, from `CategoryRepository.observeUsage()`.
    private(set) var usage: [CategoryUsage] = []

    /// User-facing message from the last failed change or observation. Nil after a successful change.
    private(set) var errorMessage: String?

    @ObservationIgnored private let categoryRepository: CategoryRepository
    @ObservationIgnored private let settings: AppSettings

    init(session: AppSession) {
        self.categoryRepository = session.environment.categoryRepository
        self.settings = session.settings
    }

    /// Runs the usage list until the calling task is cancelled.
    func observe() async {
        do {
            for try await observed in categoryRepository.observeUsage() {
                usage = observed
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = Self.message(for: error)
        }
    }

    /// Adds a custom category. Names are validated by the repository.
    func create(name: String) async {
        do {
            _ = try await categoryRepository.create(name: name)
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Renames a custom category. A built-in category sets `errorMessage` and keeps its name.
    func rename(id: String, to name: String) async {
        do {
            try await categoryRepository.rename(id: id, to: name)
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Deletes a custom category. Its documents move to Other. If it was the default category for new imports,
    /// the default goes back to Lecture slides.
    func delete(id: String) async {
        do {
            _ = try await categoryRepository.delete(id: id)
            if settings.defaultCategoryId == id {
                settings.defaultCategoryId = BuiltinCategory.lectureSlides.id
            }
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Clears the error message once the user has seen it.
    func dismissError() {
        errorMessage = nil
    }

    private static func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? String(localized: "The categories couldn't be updated. Try again.")
    }
}
