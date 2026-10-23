import Foundation

/// `document` table (ARCHITECTURE §4). `pdfPosition` is a JSON column.
struct LibraryDocument: StudyRecord, Equatable, Identifiable {
    static let databaseTableName = "document"

    var id: String
    var title: String
    var author: String = ""
    var categoryId: String
    var fileType: FileType
    var fileHash: String
    var originalFilename: String
    var originalBookmark: Data? = nil
    var storedPath: String
    var pageCount: Int? = nil
    var coverPath: String? = nil
    var coverSource: CoverSource = .automatic
    var extractionStatus: ExtractionStatus = .pending
    var extractionVersion: Int = 0
    var pdfPosition: PDFPosition? = nil
    var textPosition: Int? = nil
    var progress: Double = 0
    var addedAt: Date
    var lastOpenedAt: Date? = nil
}

/// `documentText` table (ARCHITECTURE §4). `runs` is a JSON column.
struct DocumentText: StudyRecord, Equatable {
    static let databaseTableName = "documentText"

    var documentId: String
    var unitIndex: Int
    var startOffset: Int
    var text: String
    var runs: [TextRun]? = nil
}
