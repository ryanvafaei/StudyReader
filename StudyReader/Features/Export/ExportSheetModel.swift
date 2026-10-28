import Foundation
import Observation

/// State behind the Export Highlights sheet (SPEC F-21, ADR-0018): which scope, the options, and the outcome.
/// Talks to Google only through `GoogleExportService`.
@MainActor @Observable
final class ExportSheetModel {
    enum ScopeKind: String, CaseIterable, Sendable {
        case document, tag, category, themedReview, all
    }

    var scopeKind: ScopeKind {
        didSet {
            if scopeKind != oldValue { selectedId = nil }
        }
    }
    /// The chosen document, tag, category or themed review. Ignored for `.all`.
    var selectedId: String?
    var options = ExportOptions()

    private(set) var documents: [LibraryDocument] = []
    private(set) var tags: [LibraryTag] = []
    private(set) var categories: [DocumentCategory] = []
    private(set) var themedReviews: [ThemedReview] = []
    private(set) var isConfigured = true
    private(set) var isExporting = false
    private(set) var outcome: ExportOutcome?

    @ObservationIgnored private let environment: AppEnvironment

    /// `initialScope` nil: the sheet starts on "All highlights".
    init(session: AppSession, initialScope: ExportScope?) {
        self.environment = session.environment
        switch initialScope?.kind {
        case .document: scopeKind = .document
        case .tag: scopeKind = .tag
        case .category: scopeKind = .category
        case .themedReview: scopeKind = .themedReview
        case .all, nil: scopeKind = .all
        }
        selectedId = initialScope?.id
    }

    /// nil until a required id is chosen.
    var scope: ExportScope? {
        switch scopeKind {
        case .all: return .all
        case .document: return selectedId.map(ExportScope.document)
        case .tag: return selectedId.map(ExportScope.tag)
        case .category: return selectedId.map(ExportScope.category)
        case .themedReview: return selectedId.map(ExportScope.themedReview)
        }
    }

    /// Scope kinds the picker offers: themed reviews are hidden when there are none.
    var availableKinds: [ScopeKind] {
        ScopeKind.allCases.filter { $0 != .themedReview || !themedReviews.isEmpty || scopeKind == .themedReview }
    }

    var canExport: Bool { scope != nil && !isExporting && isConfigured }

    var outcomeMessage: String? { outcome.map(Self.message(for:)) }

    var exportedFileId: String? {
        if case .exported(let fileId) = outcome { return fileId }
        return nil
    }

    var isDocMissing: Bool { outcome == .docMissing }

    // MARK: - Loading

    func load() async {
        isConfigured = await environment.googleAuth.isConfigured
        documents = (try? await environment.documentRepository.fetchAll()) ?? []
        tags = (try? await environment.tagRepository.fetchAll()) ?? []
        categories = (try? await environment.categoryRepository.fetchAll()) ?? []
        themedReviews = (try? await environment.exportRepository.fetchThemedReviews()) ?? []
        await prefillOptions()
    }

    /// Takes the saved options of the target for the current scope, when there is one.
    func prefillOptions() async {
        guard let scope else { return }
        if let target = try? await environment.exportRepository.target(for: scope), scope == self.scope {
            options = target.options
        }
    }

    // MARK: - Export

    func export() async {
        guard let scope, !isExporting else { return }
        isExporting = true
        outcome = nil
        let result = await environment.googleExportService.exportScope(scope, options: options)
        outcome = result.outcome
        isExporting = false
    }

    /// "Create New Doc" after a missing Doc: forgets the file ID of the scope's target, then exports again.
    func createNewDoc() async {
        guard let scope, !isExporting else { return }
        if let target = try? await environment.exportRepository.target(for: scope) {
            try? await environment.exportRepository.clearFileId(id: target.id)
        }
        await export()
    }

    // MARK: - Text

    /// Shared by the sheet and the browser's "Export Selection…" alert.
    nonisolated static func message(for outcome: ExportOutcome) -> String {
        switch outcome {
        case .exported: String(localized: "Exported. The Google Doc is up to date.")
        case .queued: String(localized: "You're offline. The export will run when you're back online.")
        case .signInRequired: String(localized: "Sign in to Google in Settings > Google.")
        case .docMissing: String(localized: "The Google Doc was deleted or you lost access.")
        case .notConfigured: String(localized: "Google export not configured.")
        case .cancelled: String(localized: "The export was cancelled.")
        case .failed(let text): text
        }
    }
}
