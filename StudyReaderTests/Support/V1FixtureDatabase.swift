import Foundation
import GRDB
@testable import StudyReader

/// A populated database at migration v1 only (ADR-0013). Frozen: never edit the rows below.
enum V1FixtureDatabase {
    static let documentPDF = "A1000000-0000-4000-8000-000000000001"
    static let documentMarkdown = "A1000000-0000-4000-8000-000000000002"
    static let highlightLatin = "B1000000-0000-4000-8000-000000000001"
    static let highlightMarkdown = "B1000000-0000-4000-8000-000000000002"
    static let tag = "C1000000-0000-4000-8000-000000000001"
    static let card = "D1000000-0000-4000-8000-000000000001"
    static let themedReview = "E1000000-0000-4000-8000-000000000001"
    static let logDaily = "F1000000-0000-4000-8000-000000000001"
    static let logThemed = "F1000000-0000-4000-8000-000000000002"
    static let exportTarget = "A2000000-0000-4000-8000-000000000001"

    /// findLigature + " " + photosynthesisSoftHyphen (19 UTF-16 units)
    static let markdownHighlightText = SearchSamples.findLigature + " " + SearchSamples.photosynthesisSoftHyphen

    static let expectedRowCounts: [String: Int] = [
        "category": 5, "document": 2, "documentText": 3, "highlight": 2, "tag": 1, "highlightTag": 1,
        "documentTag": 1, "documentNote": 1, "reviewCard": 1, "themedReview": 1, "reviewLog": 2,
        "exportTarget": 1, "highlightEmbedding": 1,
    ]

    /// In-memory queue with AppDatabase.makeConfiguration(), migrated up to "v1", then populated.
    static func make() throws -> DatabaseQueue {
        let queue = try DatabaseQueue(configuration: AppDatabase.makeConfiguration())
        try AppDatabase.migrator.migrate(queue, upTo: "v1")
        try queue.write { db in try populate(db) }
        return queue
    }

    /// Same database on disk at fileStore.databaseURL (root directories created), then closed.
    static func makeOnDisk(fileStore: FileStore) throws {
        try fileStore.createRootDirectories()
        let queue = try DatabaseQueue(
            path: fileStore.databaseURL.path(percentEncoded: false),
            configuration: AppDatabase.makeConfiguration())
        try AppDatabase.migrator.migrate(queue, upTo: "v1")
        try queue.write { db in try populate(db) }
        try queue.close()
    }

    static func populate(_ db: Database) throws {
        let lectureSlides = "00000000-0000-0000-0000-000000000001"
        let notes = "00000000-0000-0000-0000-000000000004"
        try db.execute(sql: """
            INSERT INTO document (id, title, author, categoryId, fileType, fileHash, originalFilename, storedPath,
              pageCount, extractionStatus, extractionVersion, pdfPosition, progress, addedAt, lastOpenedAt)
            VALUES (?, 'Cell Biology', 'Alberts', ?, 'pdf', 'v1-fixture-hash-1', 'cell-biology.pdf', ?,
              2, 'done', 1, '{"pageIndex":1,"offsetY":120.5}', 0.5, 1790000000, 1790003600)
            """, arguments: [documentPDF, lectureSlides, "\(documentPDF)/original.pdf"])
        try db.execute(sql: """
            INSERT INTO document (id, title, author, categoryId, fileType, fileHash, originalFilename, storedPath,
              extractionStatus, extractionVersion, textPosition, addedAt)
            VALUES (?, 'Lecture notes', ?, ?, 'markdown', 'v1-fixture-hash-2', 'notes.md', ?, 'done', 1, 42, 1790000100)
            """, arguments: [documentMarkdown, SearchSamples.authorWithDiacritics, notes, "\(documentMarkdown)/original.md"])
        try db.execute(sql: "INSERT INTO documentText (documentId, unitIndex, startOffset, text) VALUES (?, 0, 0, 'Photosynthesis occurs in chloroplasts')",
                       arguments: [documentPDF])
        try db.execute(sql: """
            INSERT INTO documentText (documentId, unitIndex, startOffset, text, runs)
            VALUES (?, 1, 39, 'The Krebs cycle', '[{"start":4,"length":5,"bold":true,"italic":false,"mono":false}]')
            """, arguments: [documentPDF])
        try db.execute(sql: "INSERT INTO documentText (documentId, unitIndex, startOffset, text) VALUES (?, 0, 0, ?)",
                       arguments: [documentMarkdown, SearchSamples.photosynthesisSoftHyphen])
        try db.execute(sql: """
            INSERT INTO highlight (id, documentId, kind, view, color, text, richText, note, pageIndex, positionKey, anchor, createdAt, updatedAt)
            VALUES (?, ?, 'text', 'pdf', 1, 'Mitochondria produce ATP', 'Mitochondria produce **ATP**', 'exam topic', 0, 500.0,
              '{"type":"pdf","pdf":{"pages":[{"pageIndex":0,"rects":[{"x":72,"y":500,"width":200,"height":14}]}],"text":"Mitochondria produce ATP","prefix":"","suffix":""}}',
              1790000200, 1790000200)
            """, arguments: [highlightLatin, documentPDF])
        let markdownAnchor = #"{"type":"text","text":{"start":0,"length":19,"text":""# + markdownHighlightText
            + #"","prefix":"","suffix":"","sourceVersion":1}}"#
        try db.execute(sql: """
            INSERT INTO highlight (id, documentId, kind, view, color, text, richText, positionKey, anchor, createdAt, updatedAt)
            VALUES (?, ?, 'text', 'markdown', 0, ?, ?, 0, ?, 1790000250, 1790000250)
            """, arguments: [highlightMarkdown, documentMarkdown, markdownHighlightText, markdownHighlightText, markdownAnchor])
        try db.execute(sql: "INSERT INTO tag (id, name, createdAt) VALUES (?, 'Exam', 1790000300)", arguments: [tag])
        try db.execute(sql: "INSERT INTO highlightTag (highlightId, tagId) VALUES (?, ?)", arguments: [highlightLatin, tag])
        try db.execute(sql: "INSERT INTO documentTag (documentId, tagId) VALUES (?, ?)", arguments: [documentPDF, tag])
        try db.execute(sql: "INSERT INTO documentNote (documentId, body, updatedAt) VALUES (?, 'Review before the midterm', 1790000400)",
                       arguments: [documentPDF])
        try db.execute(sql: """
            INSERT INTO reviewCard (id, highlightId, cardType, fsrsCard, dueAt, state, introducedAt, createdAt)
            VALUES (?, ?, 'passive', '{}', 1790086400, 'review', 1790000500, 1790000200)
            """, arguments: [card, highlightLatin])
        try db.execute(sql: """
            INSERT INTO themedReview (id, name, filter, cardsPerSession, interval, orderMode, createdAt)
            VALUES (?, 'Exam week', ?, 20, '{"kind":"daily"}', 'dueFirst', 1790000300)
            """, arguments: [themedReview, #"{"tagIds":["\#(tag)"],"tagMode":"any"}"#])
        try db.execute(sql: """
            INSERT INTO reviewLog (id, cardId, rating, reviewedAt, sessionKind, themedReviewId, fsrsLog)
            VALUES (?, ?, 3, 1790000600, 'daily', NULL, '{}'), (?, ?, 4, 1790001200, 'themed', ?, '{}')
            """, arguments: [logDaily, card, logThemed, card, themedReview])
        try db.execute(sql: """
            INSERT INTO exportTarget (id, title, scope, options, format, keepInSync, lastStatus, createdAt)
            VALUES (?, 'StudyReader – All highlights', '{"kind":"all"}',
              '{"includeNotes":true,"includeDocumentNotes":true,"includeImages":true,"groupBy":"document"}',
              'markdown', 0, 'never', 1790000700)
            """, arguments: [exportTarget])
        try db.execute(sql: """
            INSERT INTO highlightEmbedding (highlightId, modelId, dimension, vector, sourceHash)
            VALUES (?, 'NLEmbedding.sentence.en', 2, x'0000803F00000040', 'v1-fixture-source-hash')
            """, arguments: [highlightLatin])
    }
}
