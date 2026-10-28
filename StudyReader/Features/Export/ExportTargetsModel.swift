import Foundation
import Observation

/// Settings > Google: the export folder and the saved export targets (ADR-0018).
/// Keep-in-sync scheduling is T74; here the toggle only stores the flag.
@MainActor @Observable
final class ExportTargetsModel {
    private(set) var targets: [ExportTarget] = []
    var folderLink: String
    private(set) var folderError: String?
    /// Targets with an Export Now / Create New Doc in flight.
    private(set) var exportingIds: Set<String> = []

    @ObservationIgnored private let session: AppSession
    @ObservationIgnored private var environment: AppEnvironment { session.environment }

    init(session: AppSession) {
        self.session = session
        self.folderLink = session.settings.googleExportFolderId ?? ""
    }

    func observe() async {
        do {
            for try await list in environment.exportRepository.observeTargets() {
                targets = list
            }
        } catch is CancellationError {
        } catch {
            // The list keeps its last value.
        }
    }

    /// An empty link clears the setting. An invalid one keeps the old folder and shows an error.
    func saveFolder() {
        let trimmed = folderLink.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            session.settings.googleExportFolderId = nil
            folderLink = ""
            folderError = nil
            return
        }
        guard let id = DriveFolderLink.folderId(from: trimmed) else {
            folderError = String(localized: "That isn't a Google Drive folder link.")
            return
        }
        session.settings.googleExportFolderId = id
        folderLink = id
        folderError = nil
    }

    func exportNow(_ id: String) async {
        guard !exportingIds.contains(id) else { return }
        exportingIds.insert(id)
        defer { exportingIds.remove(id) }
        _ = await environment.googleExportService.export(targetId: id)
    }

    private func clearAndExport(_ id: String) async {
        guard !exportingIds.contains(id) else { return }
        exportingIds.insert(id)
        defer { exportingIds.remove(id) }
        try? await environment.exportRepository.clearFileId(id: id)
        _ = await environment.googleExportService.export(targetId: id)
    }

    func setKeepInSync(_ id: String, _ on: Bool) async {
        try? await environment.exportRepository.setKeepInSync(id: id, on)
    }

    /// Removes the local target only. The Google Doc stays, and no request is sent.
    func remove(_ id: String) async {
        try? await environment.exportRepository.removeTarget(id: id)
    }

    /// For a missing Doc: forgets the file ID and exports again, which creates a new Doc.
    func createNewDoc(_ id: String) async {
        await clearAndExport(id)
    }

    nonisolated static func docURL(fileId: String) -> URL {
        URL(string: "https://docs.google.com/document/d/\(fileId)/edit") ?? URL(filePath: "/")
    }

    nonisolated static func statusText(_ target: ExportTarget) -> String {
        switch ExportStatus(rawValue: target.lastStatus) ?? .never {
        case .never:
            return String(localized: "Never exported")
        case .ok:
            guard let date = target.lastExportedAt else { return String(localized: "Exported") }
            let relative = date.formatted(.relative(presentation: .named))
            return String(localized: "Exported \(relative)")
        case .queued:
            return String(localized: "Waiting for network")
        case .failed:
            let reason = target.lastError ?? ""
            return String(localized: "Failed: \(reason)")
        case .docMissing:
            return String(localized: "Doc missing")
        case .signInRequired:
            return String(localized: "Sign-in required")
        }
    }
}
