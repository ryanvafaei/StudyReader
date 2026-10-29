import Testing
import Foundation
@testable import StudyReader

/// Cloze text helper (T107, ARCHITECTURE §10.3, ADR-0021). Pure; no database.
@Suite struct ClozeTextTests {

    private static let mitochondria = "The mitochondria produce ATP."

    @Test func frontAndBack() {
        let ranges = ClozeText.normalized([[4, 12]], in: Self.mitochondria)
        #expect(ClozeText.front(Self.mitochondria, ranges: ranges) == "The \\[…\\] produce ATP.")
        #expect(ClozeText.back(Self.mitochondria, ranges: ranges) == "The **mitochondria** produce ATP.")
    }

    @Test func twoRangesMakeTwoPlaceholdersAndBoldSpans() {
        let ranges = ClozeText.normalized([[4, 12], [25, 3]], in: Self.mitochondria)
        #expect(ClozeText.front(Self.mitochondria, ranges: ranges) == "The \\[…\\] produce \\[…\\].")
        #expect(ClozeText.back(Self.mitochondria, ranges: ranges) == "The **mitochondria** produce **ATP**.")
    }

    @Test func whitespaceMovesOutsideMarkers() {
        let ranges = ClozeText.normalized([[3, 13]], in: Self.mitochondria)
        #expect(ClozeText.back(Self.mitochondria, ranges: ranges) == "The **mitochondria** produce ATP.")
    }

    @Test(arguments: [
        [[-1, 2]],
        [[0, 0]],
        [[0]],
        [[20, 50]],
        [[0, 1, 2]],
    ])
    func normalizationDropsInvalidRanges(pairs: [[Int]]) {
        #expect(ClozeText.normalized(pairs, in: Self.mitochondria).isEmpty)
    }

    @Test func normalizationSortsAndMergesOverlapping() {
        let ranges = ClozeText.normalized([[10, 3], [4, 12]], in: Self.mitochondria)
        #expect(ranges == [ClozeRange(location: 4, length: 12)])
    }

    @Test func normalizationKeepsTouchingRangesApart() {
        let ranges = ClozeText.normalized([[0, 3], [3, 2]], in: Self.mitochondria)
        #expect(ranges == [ClozeRange(location: 0, length: 3), ClozeRange(location: 3, length: 2)])
    }

    @Test func offsetsAreUTF16() {
        let text = "naïve café"
        #expect(text.utf16.count == 10)
        let ranges = ClozeText.normalized([[6, 4]], in: text)
        #expect(ranges == [ClozeRange(location: 6, length: 4)])
        #expect(ClozeText.back(text, ranges: ranges) == "naïve **café**")
        #expect(ClozeText.normalized([[6, 5]], in: text).isEmpty)
    }

    @Test func escapesMarkdown() {
        let text = "a *b* [c]"
        let ranges = ClozeText.normalized([[3, 1]], in: text)
        #expect(ClozeText.front(text, ranges: ranges) == "a \\*\\[…\\]\\* \\[c\\]")
    }
}
