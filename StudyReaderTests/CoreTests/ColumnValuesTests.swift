import Foundation
import Testing
@testable import StudyReader

@Suite struct ColumnValuesTests {
    private static func jsonObject(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private static func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @Test func missingKeysUseDefaults() throws {
        let options = try JSONDecoder().decode(ExportOptions.self, from: Data("{}".utf8))
        #expect(options == ExportOptions())

        let filter = try JSONDecoder().decode(ThemedReviewFilter.self, from: Data("{}".utf8))
        #expect(filter == ThemedReviewFilter())
    }

    @Test func encodedShapes() throws {
        let interval = try Self.jsonObject(ReviewInterval.everyNDays(3))
        #expect(interval["weekdays"] == nil)
        #expect(interval["n"] as? Int == 3)

        let scope = try Self.jsonObject(ExportScope.all)
        #expect(scope["id"] == nil)
        #expect(scope["kind"] as? String == "all")

        let filter = try Self.jsonObject(ThemedReviewFilter(colors: [.blue]))
        #expect(filter["colors"] as? [Int] == [2])
    }

    @Test func roundTrips() throws {
        let position = PDFPosition(pageIndex: 3, offsetY: 412.5)
        #expect(try Self.roundTrip(position) == position)

        let plainRun = TextRun(start: 0, length: 4, bold: true, italic: false, mono: false, link: nil)
        #expect(try Self.roundTrip(plainRun) == plainRun)

        let linkRun = TextRun(start: 4, length: 9, bold: false, italic: true, mono: true, link: "https://example.com")
        #expect(try Self.roundTrip(linkRun) == linkRun)

        for interval in [ReviewInterval.daily, .everyNDays(2), .weekdays([2, 4, 6])] {
            #expect(try Self.roundTrip(interval) == interval)
        }

        for scope in [ExportScope.all, .document("doc-1"), .tag("t"), .category("c"), .themedReview("r")] {
            #expect(try Self.roundTrip(scope) == scope)
        }

        let options = ExportOptions(includeNotes: false, includeDocumentNotes: true,
                                    includeImages: false, groupBy: .tag)
        #expect(try Self.roundTrip(options) == options)

        let filter = ThemedReviewFilter(tagIds: ["a"], tagMode: .all, documentIds: ["d"],
                                        categoryIds: ["c"], colors: [.yellow, .purple])
        #expect(try Self.roundTrip(filter) == filter)
    }
}
