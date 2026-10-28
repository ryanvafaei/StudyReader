import Testing
@testable import StudyReader

@Suite("HighlightKeys")
struct HighlightKeysTests {
    @Test
    func keysMapToColors() {
        #expect(HighlightKeys.color(forKey: "1", current: .pink) == .yellow)
        #expect(HighlightKeys.color(forKey: "3", current: .pink) == .blue)
        #expect(HighlightKeys.color(forKey: "5", current: .pink) == .purple)
        #expect(HighlightKeys.color(forKey: "h", current: .pink) == .pink)
        #expect(HighlightKeys.color(forKey: "H", current: .green) == .green)
        #expect(HighlightKeys.color(forKey: "6", current: .pink) == nil)
        #expect(HighlightKeys.color(forKey: "0", current: .pink) == nil)
        #expect(HighlightKeys.color(forKey: "x", current: .pink) == nil)
        #expect(HighlightKeys.color(forKey: nil, current: .pink) == nil)
    }
}
