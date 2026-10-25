import AppKit
import Foundation
import Observation

/// Runs imports for the app and answers the importer's questions with UI (SPEC F-02, F-03).
/// Batches run one after another in the order they were queued. A password or large-file question suspends the
/// running batch until the UI answers it. Views read the observable properties; they hold no import logic.
@MainActor @Observable
final class ImportCoordinator: ImportInteraction {
    struct PasswordRequest: Identifiable, Equatable {
        let id: UUID
        let fileName: String
    }

    struct LargeFileRequest: Identifiable, Equatable {
        let id: UUID
        let fileName: String
        let byteCount: Int64
    }

    /// Shows the folder-access panel; injected so tests never open a real panel.
    typealias FolderPanel = @MainActor (_ folder: URL, _ markdownFileName: String) async -> URL?

    /// true while a batch is queued or running.
    private(set) var isImporting = false
    /// The password question for the running batch, nil when none is pending.
    private(set) var passwordRequest: PasswordRequest?
    /// The large-file question for the running batch, nil when none is pending.
    private(set) var largeFileRequest: LargeFileRequest?
    /// Summary of the last finished import; the UI shows it in an alert and sets it to nil when dismissed.
    var lastSummary: String?
    /// Every summary produced in this app run, in order. Tests read it; the UI doesn't.
    private(set) var summaryHistory: [String] = []

    @ObservationIgnored private let importService: ImportService
    @ObservationIgnored private let folderPanel: FolderPanel
    @ObservationIgnored private var passwordContinuation: CheckedContinuation<String?, Never>?
    @ObservationIgnored private var largeFileContinuation: CheckedContinuation<Bool, Never>?
    /// The last queued batch; the next batch waits for it, which keeps batches in order.
    @ObservationIgnored private var lastBatch: Task<Void, Never>?
    @ObservationIgnored private var pendingBatches = 0

    init(
        importService: ImportService,
        folderPanel: @escaping FolderPanel = ImportCoordinator.showFolderAccessPanel
    ) {
        self.importService = importService
        self.folderPanel = folderPanel
    }

    // MARK: - Starting imports

    /// Queues the file URLs (files or folders). Non-file URLs are ignored here. Batches run one at a time.
    func importURLs(_ urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        let previous = lastBatch
        pendingBatches += 1
        isImporting = true
        lastBatch = Task {
            await previous?.value
            let report = await self.importService.importItems(at: files, interaction: self)
            self.finishBatch(report)
        }
    }

    private func finishBatch(_ report: ImportReport) {
        pendingBatches -= 1
        isImporting = pendingBatches > 0
        let summary = report.summary.isEmpty ? "Imported 0" : report.summary
        summaryHistory.append(summary)
        lastSummary = summary
    }

    // MARK: - Answers from the UI

    /// Resumes the pending password question. nil = skipped. Later calls do nothing.
    func answerPassword(_ password: String?) {
        guard let continuation = passwordContinuation else { return }
        passwordContinuation = nil
        passwordRequest = nil
        continuation.resume(returning: password)
    }

    /// Resumes the pending large-file question. Later calls do nothing.
    func answerLargeFile(_ allow: Bool) {
        guard let continuation = largeFileContinuation else { return }
        largeFileContinuation = nil
        largeFileRequest = nil
        continuation.resume(returning: allow)
    }

    // MARK: - ImportInteraction

    func confirmLargeFile(named name: String, byteCount: Int64) async -> Bool {
        await withCheckedContinuation { continuation in
            largeFileContinuation = continuation
            largeFileRequest = LargeFileRequest(id: UUID(), fileName: name, byteCount: byteCount)
        }
    }

    func password(forFileNamed name: String) async -> String? {
        await withCheckedContinuation { continuation in
            passwordContinuation = continuation
            passwordRequest = PasswordRequest(id: UUID(), fileName: name)
        }
    }

    func requestFolderAccess(for folder: URL, markdownFileName: String) async -> URL? {
        await folderPanel(folder, markdownFileName)
    }

    /// NSOpenPanel for one folder (ADR-0016, user decision Q5). Shown as a sheet on the key or main window when there
    /// is one. Returns the chosen folder, or nil when cancelled.
    static func showFolderAccessPanel(_ folder: URL, _ markdownFileName: String) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.message = String(localized: "Allow access to this folder so StudyReader can copy the images.")
        panel.prompt = String(localized: "Allow")
        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = await panel.begin()
        }
        guard response == .OK else { return nil }
        return panel.url
    }
}
