import Foundation

/// Questions the import asks the user. The UI (T48) implements it; tests use stubs.
protocol ImportInteraction: Sendable {
    /// Asked once per file larger than the threshold. true = import it.
    func confirmLargeFile(named name: String, byteCount: Int64) async -> Bool
    /// Asked once per locked PDF. nil = the user cancelled.
    func password(forFileNamed name: String) async -> String?
    /// Asked when a Markdown file's relative images can't be read (sandbox). The UI shows an NSOpenPanel for
    /// directories, preselected on `folder`, with the message "Allow access to this folder so StudyReader can copy
    /// the images." Returns the URL the user approved, or nil if cancelled (ADR-0016, user decision Q5).
    func requestFolderAccess(for folder: URL, markdownFileName: String) async -> URL?
}

/// Implemented by ExtractionService (T44).
protocol ExtractionQueue: Sendable {
    func enqueue(documentId: String) async
}

/// Imports dropped or picked files and folders (SPEC F-02, F-03, F-11) in the order of ADR-0016. Any failure after
/// the document folder exists deletes the folder again.
actor ImportService {
    static let defaultLargeFileThreshold: Int64 = 500_000_000      // 500 MB, decimal
    static let maxFolderDepth = 3

    private let fileStore: FileStore
    private let documents: DocumentRepository
    private let categories: CategoryRepository
    private let covers: CoverService
    private let settings: SettingsStore
    private let now: any Now
    private let extractionQueue: any ExtractionQueue
    private let largeFileThreshold: Int64

    init(fileStore: FileStore,
         documents: DocumentRepository,
         categories: CategoryRepository,
         covers: CoverService,
         settings: SettingsStore,
         now: any Now,
         extractionQueue: any ExtractionQueue,
         largeFileThreshold: Int64 = ImportService.defaultLargeFileThreshold) {
        self.fileStore = fileStore
        self.documents = documents
        self.categories = categories
        self.covers = covers
        self.settings = settings
        self.now = now
        self.extractionQueue = extractionQueue
        self.largeFileThreshold = largeFileThreshold
    }

    /// Imports files and folders in the given order, one file at a time.
    func importItems(at urls: [URL], interaction: any ImportInteraction) async -> ImportReport {
        var batch = Batch()
        for url in urls {
            let startedAccess = url.startAccessingSecurityScopedResource()
            switch Self.expand(url) {
            case .unsupported(let name):
                batch.report.unsupported.append(name)
            case .files(let files):
                for file in files {
                    await importFile(file, interaction: interaction, batch: &batch)
                }
            }
            if startedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        for approved in batch.startedFolderAccess {
            approved.stopAccessingSecurityScopedResource()
        }
        Log.files.info("""
            Import batch finished: \(batch.report.imported.count, privacy: .public) imported, \
            \(batch.report.duplicates.count, privacy: .public) duplicates, \
            \(batch.report.failures.count, privacy: .public) failures
            """)
        return batch.report
    }

    // MARK: - Batch state

    private struct Batch {
        var report = ImportReport()
        /// Folder → the URL the user approved, or nil when declined. Asked at most once per folder per batch.
        var folderAccess: [URL: URL?] = [:]
        /// Approved URLs already used in this batch (security-scoped access is started once).
        var usedApprovedFolders: Set<URL> = []
        /// Approved URLs whose access has to be stopped when the batch ends.
        var startedFolderAccess: [URL] = []
    }

    // MARK: - Expansion

    private enum Expansion {
        case unsupported(String)
        case files([URL])
    }

    private static func expand(_ url: URL) -> Expansion {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        guard isDirectory else {
            if FileType(fileExtension: url.pathExtension) != nil {
                return .files([url])
            }
            return .unsupported(url.lastPathComponent)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return .files([])
        }
        var files: [URL] = []
        while let item = enumerator.nextObject() as? URL {
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if values?.isDirectory == true {
                if enumerator.level >= maxFolderDepth + 1 {
                    enumerator.skipDescendants()
                }
                continue
            }
            if (1...(maxFolderDepth + 1)).contains(enumerator.level), FileType(fileExtension: item.pathExtension) != nil {
                files.append(item)
            }
        }
        return .files(files.sorted { $0.path < $1.path })
    }

    // MARK: - One file

    private struct Prepared {
        var fileType: FileType
        var fileHash: String
        var metadataTitle: String?
        var metadataAuthor: String?
        var pageCount: Int?
        /// Set when the PDF needed a password: the stored copy is written unlocked.
        var unlockPassword: String?
        /// Markdown body without front matter.
        var markdownBody: String?
    }

    private enum PrepareOutcome {
        case ready(Prepared)
        case duplicate(String)
        case failed(ImportFailureReason)
    }

    private func importFile(_ url: URL, interaction: any ImportInteraction, batch: inout Batch) async {
        let fileName = url.lastPathComponent
        let prepared: Prepared
        switch await prepare(url, interaction: interaction) {
        case .ready(let value):
            prepared = value
        case .duplicate(let title):
            batch.report.duplicates.append(title)
            return
        case .failed(let reason):
            batch.report.failures.append(ImportFailure(fileName: fileName, reason: reason))
            return
        }

        let documentId = UUID().uuidString
        let categoryId = await resolveCategoryId()
        var imageCounts = MarkdownImageCollector.CopyResult(copied: 0, missing: 0, unreadable: 0, alreadyPresent: 0)
        let title = MetadataDefaults.title(metadataTitle: prepared.metadataTitle, fileName: fileName)
        do {
            try fileStore.createDocumentFolder(documentId: documentId)
            let destination = try fileStore.originalFileURL(documentId: documentId, fileType: prepared.fileType)
            if let password = prepared.unlockPassword {
                try PDFImportInspector.writeUnlockedCopy(of: url, password: password, to: destination)
            } else {
                try FileManager.default.copyItem(at: url, to: destination)
            }
            if let body = prepared.markdownBody {
                imageCounts = try await copyMarkdownImages(
                    body: body, markdownURL: url, documentId: documentId, interaction: interaction, batch: &batch
                )
            }
            guard let storedPath = fileStore.relativePath(for: destination) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let document = LibraryDocument(
                id: documentId,
                title: title,
                author: MetadataDefaults.author(metadataAuthor: prepared.metadataAuthor),
                categoryId: categoryId,
                fileType: prepared.fileType,
                fileHash: prepared.fileHash,
                originalFilename: fileName,
                originalBookmark: try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
                storedPath: storedPath,
                pageCount: prepared.pageCount,
                addedAt: now()
            )
            try await documents.insert(document)
        } catch {
            try? fileStore.deleteDocumentFolder(documentId: documentId)
            if let existing = try? await documents.fetch(fileHash: prepared.fileHash) {
                batch.report.duplicates.append(existing.title)
            } else {
                Log.files.error("Import failed for \(documentId, privacy: .public)")
                batch.report.failures.append(ImportFailure(fileName: fileName, reason: .copyFailed))
            }
            return
        }

        batch.report.unreadableImageCount += imageCounts.unreadable
        batch.report.missingImageCount += imageCounts.missing
        if prepared.fileType == .pdf {
            do {
                try await covers.resetCover(documentId: documentId)
            } catch {
                Log.files.error("Cover failed for \(documentId, privacy: .public)")
            }
        }
        await extractionQueue.enqueue(documentId: documentId)
        batch.report.imported.append(ImportedDocument(documentId: documentId, title: title))
        Log.files.info("""
            Imported \(documentId, privacy: .public): unreadable images \(imageCounts.unreadable, privacy: .public), \
            missing images \(imageCounts.missing, privacy: .public)
            """)
    }

    /// Steps 1–4 of ADR-0016: size confirmation, hash, duplicate lookup and the open check.
    private func prepare(_ url: URL, interaction: any ImportInteraction) async -> PrepareOutcome {
        guard let fileType = FileType(fileExtension: url.pathExtension) else { return .failed(.damaged) }
        let fileName = url.lastPathComponent

        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else {
            return .failed(.copyFailed)
        }
        let byteCount = Int64(size)
        if byteCount > largeFileThreshold {
            guard await interaction.confirmLargeFile(named: fileName, byteCount: byteCount) else {
                return .failed(.declinedLargeFile)
            }
        }

        let fileHash: String
        do {
            fileHash = try Hashing.sha256Hex(ofFileAt: url)
        } catch {
            return .failed(.copyFailed)
        }

        do {
            if let existing = try await documents.fetch(fileHash: fileHash) {
                return .duplicate(existing.title)
            }
        } catch {
            return .failed(.copyFailed)
        }

        switch fileType {
        case .pdf:
            var unlockPassword: String?
            var info: PDFInfo
            switch PDFImportInspector.inspect(fileAt: url, password: nil) {
            case .ok(let value):
                info = value
            case .damaged:
                return .failed(.damaged)
            case .locked:
                guard let entered = await interaction.password(forFileNamed: fileName) else {
                    return .failed(.passwordCancelled)
                }
                switch PDFImportInspector.inspect(fileAt: url, password: entered) {
                case .ok(let value):
                    info = value
                    unlockPassword = entered
                case .locked:
                    return .failed(.wrongPassword)
                case .damaged:
                    return .failed(.damaged)
                }
            }
            return .ready(Prepared(
                fileType: .pdf, fileHash: fileHash, metadataTitle: info.title, metadataAuthor: info.author,
                pageCount: info.pageCount, unlockPassword: unlockPassword, markdownBody: nil
            ))
        case .markdown:
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return .failed(.damaged) }
            let parts = FrontMatterParser.split(text)
            return .ready(Prepared(
                fileType: .markdown, fileHash: fileHash, metadataTitle: parts.frontMatter.title,
                metadataAuthor: parts.frontMatter.author, pageCount: nil, unlockPassword: nil,
                markdownBody: parts.body
            ))
        }
    }

    private func resolveCategoryId() async -> String {
        let preferred = settings.defaultCategoryId
        if (try? await categories.fetch(id: preferred)) != nil {
            return preferred
        }
        return BuiltinCategory.lectureSlides.id
    }

    // MARK: - Markdown images

    /// Copies the relative images of `markdownURL`; when some are unreadable, asks once per folder and batch for
    /// folder access and retries (ADR-0016, Q5). No bookmark is created for the approved folder.
    private func copyMarkdownImages(
        body: String,
        markdownURL: URL,
        documentId: String,
        interaction: any ImportInteraction,
        batch: inout Batch
    ) async throws -> MarkdownImageCollector.CopyResult {
        let sources = MarkdownImageCollector.imageSources(in: body)
        let sourceFolder = markdownURL.deletingLastPathComponent()
        let imagesFolder = try fileStore.imagesFolderURL(documentId: documentId)
        let first = MarkdownImageCollector.copyImages(sources: sources, from: sourceFolder, to: imagesFolder)
        guard first.unreadable > 0 else { return first }

        let folder = sourceFolder.standardizedFileURL
        let approved: URL?
        if let answer = batch.folderAccess[folder] {
            approved = answer
        } else {
            approved = await interaction.requestFolderAccess(for: folder, markdownFileName: markdownURL.lastPathComponent)
            batch.folderAccess.updateValue(approved, forKey: folder)
        }
        guard let approved else { return first }

        if batch.usedApprovedFolders.insert(approved).inserted,
           approved.startAccessingSecurityScopedResource() {
            batch.startedFolderAccess.append(approved)
        }
        return MarkdownImageCollector.copyImages(sources: sources, from: sourceFolder, to: imagesFolder)
    }
}
