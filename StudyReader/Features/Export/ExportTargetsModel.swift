import Foundation
import Observation

/// Settings > Google: the export folder and the saved export targets (ADR-0018).
/// Keep-in-sync scheduling is T74; here the toggle only stores the flag.
@MainActor @Observable
final class ExportTargetsModel {
    private(set) var targets: [ExportTarget] = []
    /// Targets with an Export Now / Create New Doc in flight.
    private(set) var exportingIds: Set<String> = []
    /// The StudyReader folder's ID for the account last passed to `refreshAppFolder(account:)` (nil when signed out or
    /// before the first export). Read from `SettingsStore.googleAppFolderId(forAccount:)`.
    private(set) var appFolderId: String?
    /// true after `consumeLegacyFolderNotice()` found a pasted folder ID saved by an older build.
    private(set) var showsLegacyFolderNotice = false

    @ObservationIgnored private let session: AppSession
    @ObservationIgnored private var environment: AppEnvironment { session.environment }
    @ObservationIgnored private var appFolderAccount: String?

    init(session: AppSession) {
        self.session = session
    }

    /// Re-reads `appFolderId` for `email` (nil email → nil) and remembers `email` for the refresh after an export.
    func refreshAppFolder(account email: String?) {
        appFolderAccount = email
        appFolderId = email.flatMap { environment.settingsStore.googleAppFolderId(forAccount: $0) }
    }

    /// Reads and removes the legacy key; sets `showsLegacyFolderNotice` when it held a non-empty value.
    func consumeLegacyFolderNotice() {
        let store = environment.settingsStore
        let legacy = store.legacyGoogleExportFolderId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !legacy.isEmpty {
            showsLegacyFolderNotice = true
        }
        store.legacyGoogleExportFolderId = nil
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

    func exportNow(_ id: String) async {
        guard !exportingIds.contains(id) else { return }
        exportingIds.insert(id)
        defer {
            exportingIds.remove(id)
            refreshAppFolder(account: appFolderAccount)
        }
        let outcome = await environment.googleExportService.export(targetId: id)
        await environment.exportSyncScheduler.manualExportEnded(targetId: id, outcome: outcome)
    }

    private func clearAndExport(_ id: String) async {
        guard !exportingIds.contains(id) else { return }
        exportingIds.insert(id)
        defer {
            exportingIds.remove(id)
            refreshAppFolder(account: appFolderAccount)
        }
        try? await environment.exportRepository.clearFileId(id: id)
        let outcome = await environment.googleExportService.export(targetId: id)
        await environment.exportSyncScheduler.manualExportEnded(targetId: id, outcome: outcome)
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

    /// https://drive.google.com/drive/folders/<id>
    nonisolated static func folderURL(folderId: String) -> URL {
        URL(string: "https://drive.google.com/drive/folders/\(folderId)") ?? URL(filePath: "/")
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
