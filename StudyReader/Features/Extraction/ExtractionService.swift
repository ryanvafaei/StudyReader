import Foundation
import GRDB

/// Background text extraction after import (SPEC F-02 step 5, F-12; ADR-0016). Documents are extracted one at a time
/// in enqueue order. A failure marks the document `.failed` and the queue continues with the next id.
actor ExtractionService: ExtractionQueue {
    enum ExtractionError: Error, Equatable {
        /// The stored file is missing or its path does not resolve inside `Documents/`.
        case missingFile
    }

    private let documents: DocumentRepository
    private let texts: DocumentTextRepository
    private let fileStore: FileStore

    /// Ids waiting to run, in order. The running id stays in `queued` until it finishes.
    private var pending: [String] = []
    private var queued: Set<String> = []
    private var workerTask: Task<Void, Never>?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    init(database: AppDatabase, fileStore: FileStore) {
        self.documents = DocumentRepository(database: database)
        self.texts = DocumentTextRepository(database: database)
        self.fileStore = fileStore
    }

    /// Adds the id unless it is queued or running; starts the worker if it is idle. Returns immediately.
    func enqueue(documentId: String) {
        guard !queued.contains(documentId) else { return }
        queued.insert(documentId)
        pending.append(documentId)
        if workerTask == nil {
            workerTask = Task { await self.drain() }
        }
    }

    /// Returns once the queue is empty and the worker is idle.
    func waitUntilIdle() async {
        if workerTask == nil && pending.isEmpty { return }
        await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }

    /// Extracts one document now. Throws on file errors after marking the document `.failed`. A document that no
    /// longer exists is skipped without error.
    func extract(documentId: String) async throws {
        guard let document = try await documents.fetch(id: documentId) else {
            Log.files.info("Extraction skipped, document gone: \(documentId, privacy: .public)")
            return
        }
        do {
            let (units, version) = try await buildUnits(for: document)
            let written = try await texts.replaceUnits(units, documentId: documentId, version: version)
            if written {
                Log.files.info("Extracted \(documentId, privacy: .public): \(units.count, privacy: .public) units")
            } else {
                Log.files.info("Extraction discarded, document gone: \(documentId, privacy: .public)")
            }
        } catch {
            try? await texts.markFailed(documentId: documentId)
            Log.files.error("Extraction failed for \(documentId, privacy: .public): \(String(describing: type(of: error)), privacy: .public)")
            throw error
        }
    }

    // MARK: - Queue

    private func drain() async {
        while !pending.isEmpty {
            let id = pending.removeFirst()
            do {
                try await extract(documentId: id)
            } catch {
                // Already logged and marked failed in `extract`; the queue continues.
            }
            queued.remove(id)
        }
        workerTask = nil
        let waiters = idleWaiters
        idleWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    // MARK: - Units

    /// Builds the `documentText` rows and the extractor version for one document. PDFKit runs in a detached task
    /// that opens its own document; only Sendable values cross the actor boundary.
    private func buildUnits(for document: LibraryDocument) async throws -> ([DocumentText], Int) {
        guard let url = fileStore.url(forRelativePath: document.storedPath),
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else {
            throw ExtractionError.missingFile
        }
        let documentId = document.id
        switch document.fileType {
        case .pdf:
            let pages = try await Task.detached {
                try PDFTextExtractor.extract(fileAt: url)
            }.value
            let offsets = PDFTextExtractor.startOffsets(pages)
            let units = zip(pages, offsets).map { page, offset in
                DocumentText(
                    documentId: documentId,
                    unitIndex: page.pageIndex,
                    startOffset: offset,
                    text: page.text,
                    runs: page.runs.isEmpty ? nil : page.runs
                )
            }
            return (units, PDFTextExtractor.version)
        case .markdown:
            let store = fileStore
            let (string, sections) = try await Task.detached {
                let markdown = try String(contentsOf: url, encoding: .utf8)
                let rendered = MarkdownRenderer.render(
                    MarkdownDocumentSource(markdown: markdown, documentId: documentId, fileStore: store)
                )
                return (rendered.string, rendered.sections)
            }.value
            let text = string as NSString
            let units = sections.enumerated().map { index, range in
                DocumentText(
                    documentId: documentId,
                    unitIndex: index,
                    startOffset: range.location,
                    text: text.substring(with: range),
                    runs: nil
                )
            }
            return (units, MarkdownRenderer.version)
        }
    }
}
