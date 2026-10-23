import Foundation

/// `exportTarget` table (ARCHITECTURE §4). `scope` and `options` are JSON columns.
/// `lastStatus` values are defined by the export task in Phase 1.
struct ExportTarget: StudyRecord, Equatable, Identifiable {
    static let databaseTableName = "exportTarget"

    var id: String
    var title: String
    var scope: ExportScope
    var options: ExportOptions = ExportOptions()
    var googleFileId: String? = nil
    var googleFolderId: String? = nil
    var format: ExportFormat = .markdown
    var keepInSync: Bool = false
    var lastExportedAt: Date? = nil
    var lastStatus: String = "never"
    var lastError: String? = nil
    var createdAt: Date
}
