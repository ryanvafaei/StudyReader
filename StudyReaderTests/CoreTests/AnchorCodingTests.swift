import CoreGraphics
import Foundation
import Testing
@testable import StudyReader

@Suite struct AnchorCodingTests {
    private static let pdf = HighlightAnchor.pdf(PDFAnchor(
        pages: [.init(pageIndex: 2, rects: [CGRectCodable(x: 10, y: 20, width: 100, height: 12)])],
        text: "selected", prefix: "before ", suffix: " after"))

    private static let text = HighlightAnchor.text(TextAnchor(
        start: 10, length: 5, text: "hello", prefix: "say ", suffix: " world", sourceVersion: 1))

    private static let image = HighlightAnchor.image(ImageAnchor(
        pageIndex: 4, rect: CGRectCodable(x: 1, y: 2, width: 3, height: 4)))

    @Test func roundTripAllCases() throws {
        for anchor in [Self.pdf, Self.text, Self.image] {
            let data = try JSONEncoder().encode(anchor)
            let decoded = try JSONDecoder().decode(HighlightAnchor.self, from: data)
            #expect(decoded == anchor)
        }
    }

    @Test func pdfAnchorJSONShape() throws {
        let data = try JSONEncoder().encode(Self.pdf)
        let object = try JSONSerialization.jsonObject(with: data)
        let root = try #require(object as? [String: Any])

        #expect(root.keys.sorted() == ["pdf", "type"])
        #expect(root["type"] as? String == "pdf")

        let payload = try #require(root["pdf"] as? [String: Any])
        let pages = try #require(payload["pages"] as? [[String: Any]])
        let rects = try #require(pages.first?["rects"] as? [[String: Any]])
        let rect = try #require(rects.first)
        #expect(rect.keys.sorted() == ["height", "width", "x", "y"])
    }

    @Test func decodesTextAnchorLiteral() throws {
        let json = #"{"type":"text","text":{"start":10,"length":5,"text":"hello","prefix":"say ","suffix":" world","sourceVersion":1}}"#
        let decoded = try JSONDecoder().decode(HighlightAnchor.self, from: Data(json.utf8))
        #expect(decoded == .text(TextAnchor(
            start: 10, length: 5, text: "hello", prefix: "say ", suffix: " world", sourceVersion: 1)))
    }

    @Test func unknownTypeThrows() {
        let json = Data(#"{"type":"bogus"}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(HighlightAnchor.self, from: json)
        }
    }

    @Test func cgRectCodableConverts() {
        let original = CGRect(x: 1.5, y: 2, width: 3, height: 4)
        #expect(CGRectCodable(original).cgRect == original)
    }
}
