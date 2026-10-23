import Testing
@testable import StudyReader

@Suite struct ModelEnumTests {
    @Test func rawValuesMatchSchema() {
        #expect(FileType.allCases.map(\.rawValue) == ["pdf", "markdown"])
        #expect(CoverSource.allCases.map(\.rawValue) == ["default", "custom", "page"])
        #expect(ExtractionStatus.allCases.map(\.rawValue) == ["pending", "done", "failed"])
        #expect(HighlightKind.allCases.map(\.rawValue) == ["text", "image"])
        #expect(ReaderViewKind.allCases.map(\.rawValue) == ["pdf", "text", "markdown"])
        #expect(AnchorStatus.allCases.map(\.rawValue) == ["ok", "orphaned"])
        #expect(ReviewFrequency.allCases.map(\.rawValue) == ["off", "low", "normal", "high"])
        #expect(CardType.allCases.map(\.rawValue) == ["passive", "cloze", "qa"])
        #expect(CardState.allCases.map(\.rawValue) == ["new", "learning", "review", "relearning"])
        #expect(SuspendedReason.allCases.map(\.rawValue) == ["mastery", "frequencyOff", "user"])
        #expect(ReviewSessionKind.allCases.map(\.rawValue) == ["daily", "themed"])
        #expect(ReviewOrderMode.allCases.map(\.rawValue) == ["dueFirst", "random"])
        #expect(ExportFormat.allCases.map(\.rawValue) == ["markdown", "html"])
        #expect(HighlightColor.allCases.map(\.rawValue) == [0, 1, 2, 3, 4])
    }
}
