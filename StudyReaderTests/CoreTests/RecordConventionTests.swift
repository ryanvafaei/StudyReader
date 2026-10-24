import GRDB
import Testing
@testable import StudyReader

@Suite struct RecordConventionTests {
    /// ADR-0012: no record may use REPLACE for insert or update.
    @Test func noReplaceConflictPolicy() {
        expectAbort(DocumentCategory.self)
        expectAbort(LibraryDocument.self)
        expectAbort(DocumentText.self)
        expectAbort(Highlight.self)
        expectAbort(LibraryTag.self)
        expectAbort(HighlightTag.self)
        expectAbort(DocumentTag.self)
        expectAbort(DocumentNote.self)
        expectAbort(ReviewCard.self)
        expectAbort(ReviewLogEntry.self)
        expectAbort(ThemedReview.self)
        expectAbort(ExportTarget.self)
        expectAbort(HighlightEmbedding.self)
    }

    private func expectAbort<T: PersistableRecord>(_: T.Type, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(T.persistenceConflictPolicy.conflictResolutionForInsert == .abort, sourceLocation: sourceLocation)
        #expect(T.persistenceConflictPolicy.conflictResolutionForUpdate == .abort, sourceLocation: sourceLocation)
    }
}
