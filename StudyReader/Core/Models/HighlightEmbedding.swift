import Foundation

/// `highlightEmbedding` table (ARCHITECTURE §4, §11). `vector` is a Float32 little-endian BLOB.
struct HighlightEmbedding: StudyRecord, Equatable {
    static let databaseTableName = "highlightEmbedding"

    var highlightId: String
    var modelId: String                      // e.g. "NLEmbedding.sentence.en"
    var dimension: Int
    var vector: Data                         // Float32 little-endian (BLOB)
    var sourceHash: String
}
