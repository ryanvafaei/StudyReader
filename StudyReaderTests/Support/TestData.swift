import Foundation
@testable import StudyReader

/// Factory for records in tests. Defaults mirror SQL defaults; ids are fresh UUID strings.
enum TestData {
    /// Whole-second date so REAL round-trips are exact.
    static let referenceDate = Date(timeIntervalSince1970: 1_790_000_000)

    static func document(
        id: String = UUID().uuidString,
        title: String = "Test Document",
        author: String = "",
        categoryId: String = BuiltinCategory.lectureSlides.id,
        fileType: FileType = .pdf,
        fileHash: String? = nil,
        addedAt: Date = referenceDate
    ) -> LibraryDocument {
        let ext = fileType == .pdf ? "pdf" : "md"
        return LibraryDocument(
            id: id,
            title: title,
            author: author,
            categoryId: categoryId,
            fileType: fileType,
            fileHash: fileHash ?? "hash-\(id)",
            originalFilename: "test.\(ext)",
            storedPath: "\(id)/original.\(ext)",
            addedAt: addedAt
        )
    }

    static func highlight(
        documentId: String,
        id: String = UUID().uuidString,
        text: String = "Sample highlight text",
        note: String = "",
        color: HighlightColor = .yellow,
        positionKey: Double = 0,
        createdAt: Date = referenceDate
    ) -> Highlight {
        Highlight(
            id: id,
            documentId: documentId,
            kind: .text,
            view: .markdown,
            color: color,
            text: text,
            richText: text,
            note: note,
            positionKey: positionKey,
            anchor: .text(TextAnchor(
                start: Int(positionKey),
                length: text.utf16.count,
                text: text,
                prefix: "",
                suffix: "",
                sourceVersion: 1
            )),
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    static func tag(name: String, id: String = UUID().uuidString, createdAt: Date = referenceDate) -> LibraryTag {
        LibraryTag(id: id, name: name, createdAt: createdAt)
    }

    static func reviewCard(
        highlightId: String,
        id: String = UUID().uuidString,
        cardType: CardType = .passive,
        dueAt: Date = referenceDate,
        state: ReviewCardState = .new,
        createdAt: Date = referenceDate
    ) -> ReviewCard {
        ReviewCard(
            id: id,
            highlightId: highlightId,
            cardType: cardType,
            fsrsCard: "{}",
            dueAt: dueAt,
            state: state,
            createdAt: createdAt
        )
    }

    static func themedReview(
        name: String = "Exam week",
        id: String = UUID().uuidString,
        createdAt: Date = referenceDate
    ) -> ThemedReview {
        ThemedReview(id: id, name: name, createdAt: createdAt)
    }

    static func exportTarget(
        scope: ExportScope = .all,
        id: String = UUID().uuidString,
        createdAt: Date = referenceDate
    ) -> ExportTarget {
        ExportTarget(
            id: id,
            title: "StudyReader – All highlights",
            scope: scope,
            createdAt: createdAt
        )
    }
}
