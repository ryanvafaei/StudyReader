import Foundation
import PDFKit

struct PDFInfo: Sendable, Equatable {
    var pageCount: Int
    var title: String?
    var author: String?
    var isEncrypted: Bool
}

enum PDFInspectionResult: Sendable, Equatable {
    case ok(PDFInfo)
    /// Needs a password, or the given one is wrong.
    case locked
    /// `PDFDocument(url:)` is nil, or the document has no pages.
    case damaged
}

enum PDFImportError: Error, Equatable {
    case locked
    case writeFailed
}

/// PDF checks for import. Every call opens its own `PDFDocument`; no PDFKit object leaves this type (ARCHITECTURE §3).
enum PDFImportInspector {
    /// Opens its own `PDFDocument(url:)`. If it is locked: a nil password gives `.locked`, and so does a password
    /// that `unlock(withPassword:)` rejects.
    static func inspect(fileAt url: URL, password: String?) -> PDFInspectionResult {
        guard let document = PDFDocument(url: url) else { return .damaged }
        if document.isLocked {
            guard let password, document.unlock(withPassword: password) else { return .locked }
        }
        guard document.pageCount > 0 else { return .damaged }
        let attributes = document.documentAttributes
        return .ok(PDFInfo(
            pageCount: document.pageCount,
            title: attributes?[PDFDocumentAttribute.titleAttribute] as? String,
            author: attributes?[PDFDocumentAttribute.authorAttribute] as? String,
            isEncrypted: document.isEncrypted
        ))
    }

    /// Unlocks with `password` and writes the document to `destination` with PDFKit, so the copy opens without a
    /// password and keeps the outline and other document data. `write(to:)` without options would keep the original
    /// password, so both passwords are written as empty strings. The copy still carries the PDF encryption
    /// dictionary (`isEncrypted` stays true) but `isLocked` is false. Never writes to `url`.
    /// - Throws: `PDFImportError.locked` when the file needs a password the given one doesn't satisfy;
    ///   `PDFImportError.writeFailed` when the file can't be opened, `destination` is `url`, or PDFKit can't write.
    static func writeUnlockedCopy(of url: URL, password: String, to destination: URL) throws {
        guard url.standardizedFileURL != destination.standardizedFileURL else { throw PDFImportError.writeFailed }
        guard let document = PDFDocument(url: url) else { throw PDFImportError.writeFailed }
        if document.isLocked {
            guard document.unlock(withPassword: password) else { throw PDFImportError.locked }
        }
        let options: [PDFDocumentWriteOption: Any] = [
            .ownerPasswordOption: "",
            .userPasswordOption: "",
        ]
        guard document.write(to: destination, withOptions: options) else { throw PDFImportError.writeFailed }
    }
}
