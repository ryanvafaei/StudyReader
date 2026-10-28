import Foundation
import Observation

/// Edits one note: a highlight's note or a document's note (SPEC F-09, F-10). The popover, side panel and
/// browser share it. Every edit schedules a save `autosaveDelay` later; `flush()` saves now.
@MainActor @Observable
final class NoteEditorModel: PendingWriteFlushing {
    enum Target: Equatable, Sendable {
        case highlight(String)
        case document(String)
    }

    static let autosaveDelay: Duration = .milliseconds(500)

    let target: Target

    /// Set by the view on every edit. Setting it schedules a save, once `load()` has finished.
    var text: String = "" {
        didSet {
            guard isLoaded else { return }
            scheduleSave()
        }
    }

    private(set) var isLoaded = false
    /// User-facing message from the last failed save or load. Nil after a successful save.
    private(set) var lastError: String?

    @ObservationIgnored private let notes: NotesRepository
    @ObservationIgnored private let highlights: HighlightRepository
    @ObservationIgnored private let tags: TagRepository
    @ObservationIgnored private let now: any Now
    @ObservationIgnored private let debouncer: Debouncer
    /// The last tail of the chain of scheduling tasks. Each edit appends one, so schedules land in edit order.
    @ObservationIgnored private var scheduling: Task<Void, Never>?
    /// The text last loaded or saved. Saving this text again does nothing.
    @ObservationIgnored private var savedText = ""

    init(target: Target, environment: AppEnvironment) {
        self.target = target
        self.notes = environment.notesRepository
        self.highlights = environment.highlightRepository
        self.tags = environment.tagRepository
        self.now = environment.now
        self.debouncer = Debouncer(delay: Self.autosaveDelay, sleeper: environment.sleeper)
        environment.pendingWrites.register(self)
    }

    func flushPendingWrites() async {
        await flush()
    }

    /// Loads the stored text without scheduling a save. On failure `isLoaded` stays false, so no save can
    /// overwrite the stored note with empty text.
    func load() async {
        do {
            let stored: String
            switch target {
            case .document(let documentId):
                stored = try await notes.documentNote(documentId: documentId)?.body ?? ""
            case .highlight(let highlightId):
                stored = try await highlights.fetch(id: highlightId)?.note ?? ""
            }
            savedText = stored
            text = stored
            lastError = nil
            isLoaded = true
        } catch {
            lastError = Self.message(for: error)
        }
    }

    /// Saves the pending text now and waits for the write. Views call it on disappear.
    func flush() async {
        await scheduling?.value
        await debouncer.cancel()
        await save()
    }

    private func scheduleSave() {
        let previous = scheduling
        let debouncer = debouncer
        scheduling = Task { [weak self] in
            await previous?.value
            await debouncer.schedule { [weak self] in
                await self?.save()
            }
        }
    }

    /// Writes the current text unless it equals the last loaded or saved text.
    private func save() async {
        guard isLoaded else { return }
        let snapshot = text
        guard snapshot != savedText else { return }
        do {
            try await write(snapshot)
            savedText = snapshot
            lastError = nil
        } catch {
            lastError = Self.message(for: error)
        }
    }

    /// Replaces the note (document body or highlight note), then adds each `#tag` in it to the document or highlight.
    /// Tags are only added, so removing `#x` from the note leaves the tag in place.
    private func write(_ body: String) async throws {
        let date = now()
        switch target {
        case .document(let documentId):
            try await notes.saveDocumentNote(documentId: documentId, body: body, at: date)
            for name in TagParsing.hashTags(in: body) {
                let tag = try await tags.findOrCreate(name: name, at: date)
                try await tags.addTag(tag.id, toDocuments: [documentId])
            }
        case .highlight(let highlightId):
            try await highlights.updateNote(id: highlightId, note: body, at: date)
            for name in TagParsing.hashTags(in: body) {
                let tag = try await tags.findOrCreate(name: name, at: date)
                try await tags.addTag(tag.id, toHighlights: [highlightId])
            }
        }
    }

    private static func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "The note couldn't be saved. Try again."
    }
}
