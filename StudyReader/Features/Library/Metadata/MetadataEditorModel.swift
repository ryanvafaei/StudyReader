import Foundation
import Observation

/// Logic for the Edit Metadata sheet (SPEC F-11): title, author and category, plus cover actions.
/// Title, author and category are saved by `save()`. Cover changes are saved at once, as the cover service does.
@MainActor @Observable
final class MetadataEditorModel {
    let documentId: String

    private(set) var document: LibraryDocument?

    var title: String = "" {
        didSet {
            if title != oldValue { titleError = nil }
        }
    }
    var author: String = ""
    var categoryId: String = ""

    /// Every category, for the picker. Loaded once in `load()`.
    private(set) var categories: [DocumentCategory] = []

    /// false until the first `load()` has finished (successfully or not). The sheet hides its fields until then.
    private(set) var hasLoaded = false

    /// Message for the Title field, shown directly below it. Set when Save is refused for a blank title; cleared when
    /// `title` changes. `errorMessage` stays for every other failure (load, save, cover).
    private(set) var titleError: String?

    /// User-facing message from the last failed load, save or cover action. Nil after a success.
    private(set) var errorMessage: String?

    /// Bumped after every cover change so the cover view reloads its image (`DocumentCoverView` reads once per path).
    private(set) var coverVersion: Int = 0

    /// Set when the sheet is opened from a PDF reader; enables "Use Current Page".
    @ObservationIgnored private let currentPageIndex: Int?
    @ObservationIgnored private let documents: DocumentRepository
    @ObservationIgnored private let categoryRepository: CategoryRepository
    @ObservationIgnored private let coverService: CoverService

    init(documentId: String, currentPageIndex: Int?, session: AppSession) {
        self.documentId = documentId
        self.currentPageIndex = currentPageIndex
        self.documents = session.environment.documentRepository
        self.categoryRepository = session.environment.categoryRepository
        self.coverService = CoverService(
            fileStore: session.environment.fileStore,
            documents: session.environment.documentRepository
        )
    }

    /// true for a PDF opened in a reader (a current page exists). Markdown never has pages.
    var canUseCurrentPage: Bool {
        document?.fileType == .pdf && currentPageIndex != nil
    }

    /// true when `categoryId` is one of `categories`, so the Category picker has a tag for its selection.
    /// false before `load()` finishes, and after a failed load.
    var hasValidCategorySelection: Bool {
        categories.contains { $0.id == categoryId }
    }

    /// Name of the selected category, or an empty string while it is unknown.
    var selectedCategoryName: String {
        categories.first { $0.id == categoryId }?.name ?? ""
    }

    /// Reads the document and the category list, and fills the fields with the stored values.
    func load() async {
        defer { hasLoaded = true }
        do {
            categories = try await categoryRepository.fetchAll()
            guard let loaded = try await documents.fetch(id: documentId) else {
                errorMessage = String(localized: "This document no longer exists.")
                return
            }
            document = loaded
            title = loaded.title
            author = loaded.author
            categoryId = loaded.categoryId
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Saves title, author and category. An empty title is refused and sets `titleError`.
    /// Returns true on success, which closes the sheet.
    func save() async -> Bool {
        do {
            try await documents.updateMetadata(id: documentId, title: title, author: author, categoryId: categoryId)
            errorMessage = nil
            titleError = nil
            return true
        } catch DocumentEditError.emptyTitle {
            titleError = Self.message(for: DocumentEditError.emptyTitle)
            return false
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    /// Makes the user-chosen image the cover. The URL comes from the file importer, so its security scope is opened here.
    func chooseCoverImage(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        await runCoverChange {
            try await coverService.setCustomCover(documentId: documentId, imageURL: url)
        }
    }

    /// Renders the page the reader is showing as the cover. Does nothing unless `canUseCurrentPage`.
    func useCurrentPageAsCover() async {
        guard canUseCurrentPage, let pageIndex = currentPageIndex else { return }
        await runCoverChange {
            try await coverService.usePageAsCover(documentId: documentId, pageIndex: pageIndex)
        }
    }

    /// Restores the automatic cover: the first page of a PDF, or the generated card for Markdown.
    func resetCover() async {
        await runCoverChange {
            try await coverService.resetCover(documentId: documentId)
        }
    }

    /// Clears the error message once the user has seen it.
    func dismissError() {
        errorMessage = nil
    }

    /// Runs one cover change, then re-reads the row so `document` shows the new cover path and source.
    private func runCoverChange(_ change: () async throws -> Void) async {
        do {
            try await change()
            document = try await documents.fetch(id: documentId)
            coverVersion += 1
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private static func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? String(localized: "The document couldn't be updated. Try again.")
    }
}
