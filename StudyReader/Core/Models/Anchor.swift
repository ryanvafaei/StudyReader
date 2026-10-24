import Foundation
import CoreGraphics

/// Stable JSON shape {"x","y","width","height"} (CGRect's own Codable uses nested arrays).
struct CGRectCodable: Codable, Sendable, Equatable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct PDFAnchor: Codable, Sendable, Equatable {
    struct PageRects: Codable, Sendable, Equatable {
        var pageIndex: Int
        var rects: [CGRectCodable]      // PDF page space, one per line (ARCHITECTURE §5.1)
    }
    var pages: [PageRects]
    var text: String
    var prefix: String                  // up to 32 chars before
    var suffix: String                  // up to 32 chars after
}

struct TextAnchor: Codable, Sendable, Equatable {
    var start: Int                      // UTF-16 offset
    var length: Int                     // UTF-16 length
    var text: String
    var prefix: String
    var suffix: String
    var sourceVersion: Int
}

struct ImageAnchor: Codable, Sendable, Equatable {
    var pageIndex: Int
    var rect: CGRectCodable
}

/// Stored as JSON in highlight.anchor. Encodes as {"type": "<case>", "<case>": {...}}. Named HighlightAnchor to avoid SwiftUI.Anchor (ADR-0012).
enum HighlightAnchor: Codable, Sendable, Equatable {
    case pdf(PDFAnchor)
    case text(TextAnchor)
    case image(ImageAnchor)

    private enum CodingKeys: String, CodingKey {
        case type, pdf, text, image
    }

    private enum Kind: String, Codable {
        case pdf, text, image
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try container.decode(String.self, forKey: .type)
        guard let kind = Kind(rawValue: rawType) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container, debugDescription: "Unknown anchor type")
        }
        switch kind {
        case .pdf:
            self = .pdf(try container.decode(PDFAnchor.self, forKey: .pdf))
        case .text:
            self = .text(try container.decode(TextAnchor.self, forKey: .text))
        case .image:
            self = .image(try container.decode(ImageAnchor.self, forKey: .image))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pdf(let anchor):
            try container.encode(Kind.pdf, forKey: .type)
            try container.encode(anchor, forKey: .pdf)
        case .text(let anchor):
            try container.encode(Kind.text, forKey: .type)
            try container.encode(anchor, forKey: .text)
        case .image(let anchor):
            try container.encode(Kind.image, forKey: .type)
            try container.encode(anchor, forKey: .image)
        }
    }
}
