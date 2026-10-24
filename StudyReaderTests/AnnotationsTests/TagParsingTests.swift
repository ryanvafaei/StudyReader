import Testing
@testable import StudyReader

@Suite("TagParsing")
struct TagParsingTests {
    @Test(.timeLimit(.minutes(1)))
    func hashTags() {
        #expect(TagParsing.hashTags(in: "Review #Exam and #ml-basics, see #exam") == ["Exam", "ml-basics"])
        #expect(TagParsing.hashTags(in: "# Heading") == [])
        #expect(TagParsing.hashTags(in: "a#b") == [])
        #expect(TagParsing.hashTags(in: "(#tag)") == ["tag"])
        #expect(TagParsing.hashTags(in: "`#code` #real") == ["real"])
        #expect(TagParsing.hashTags(in: "##x") == [])
        #expect(TagParsing.hashTags(in: "#" + String(repeating: "a", count: 41)) == [])
        #expect(TagParsing.hashTags(in: "#\u{00DC}ber") == ["\u{00DC}ber"])
        #expect(TagParsing.hashTags(in: "line1\n#next") == ["next"])

        // Extra: the 40-character limit is inclusive.
        #expect(TagParsing.hashTags(in: "#" + String(repeating: "a", count: 40)) == [String(repeating: "a", count: 40)])
    }
}
