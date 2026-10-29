import Testing
@testable import StudyReader

@Suite("ReviewStrings")
struct ReviewStringsTests {
    @Test func pluralCounts() {
        #expect(ReviewStrings.cardsToReview(1) == "1 card to review")
        #expect(ReviewStrings.cardsToReview(8) == "8 cards to review")
        #expect(ReviewStrings.reviewed(1) == "Reviewed 1 card")
        #expect(ReviewStrings.reviewed(3) == "Reviewed 3 cards")
        #expect(ReviewStrings.dueAndNew(due: 4, new: 4) == "4 due · 4 new")
    }
}
