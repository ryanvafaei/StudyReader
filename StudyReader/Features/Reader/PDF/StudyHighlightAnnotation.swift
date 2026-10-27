import AppKit
import PDFKit

/// Pure rect math shared by the annotation and its tests.
enum PDFHighlightGeometry {
    /// Union of the rects (`.zero` for an empty list).
    static func bounds(of rects: [CGRect]) -> CGRect {
        guard let first = rects.first else { return .zero }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    /// 4 points per rect, relative to `origin`, in PDFKit quad order:
    /// (minX, maxY), (maxX, maxY), (minX, minY), (maxX, minY).
    static func quadrilateralPoints(for rects: [CGRect], relativeTo origin: CGPoint) -> [CGPoint] {
        var points: [CGPoint] = []
        points.reserveCapacity(rects.count * 4)
        for rect in rects {
            let minX = rect.minX - origin.x
            let maxX = rect.maxX - origin.x
            let minY = rect.minY - origin.y
            let maxY = rect.maxY - origin.y
            points.append(CGPoint(x: minX, y: maxY))
            points.append(CGPoint(x: maxX, y: maxY))
            points.append(CGPoint(x: minX, y: minY))
            points.append(CGPoint(x: maxX, y: minY))
        }
        return points
    }
}

/// Display-only highlight (ARCHITECTURE §5.1); never saved into the file. One per page entry of a highlight.
@MainActor
final class StudyHighlightAnnotation: PDFAnnotation {
    let highlightId: String
    let createdAt: Date

    init(highlightId: String, createdAt: Date, pageRects: [CGRect], color: NSColor) {
        self.highlightId = highlightId
        self.createdAt = createdAt
        let bounds = PDFHighlightGeometry.bounds(of: pageRects)
        super.init(bounds: bounds, forType: .highlight, withProperties: nil)
        self.color = color
        quadrilateralPoints = PDFHighlightGeometry
            .quadrilateralPoints(for: pageRects, relativeTo: bounds.origin)
            .map { NSValue(point: $0) }
        shouldPrint = false
    }

    /// Display annotations are built from the database, never decoded.
    required init?(coder: NSCoder) {
        return nil
    }
}

extension StudyHighlightAnnotation {
    /// One annotation per `PDFAnchor.PageRects` entry; empty for non-PDF anchors.
    static func annotations(
        for highlight: Highlight,
        color: NSColor
    ) -> [(pageIndex: Int, annotation: StudyHighlightAnnotation)] {
        guard case .pdf(let anchor) = highlight.anchor else { return [] }
        return anchor.pages.compactMap { entry in
            guard !entry.rects.isEmpty else { return nil }
            let annotation = StudyHighlightAnnotation(
                highlightId: highlight.id,
                createdAt: highlight.createdAt,
                pageRects: entry.rects.map(\.cgRect),
                color: color
            )
            return (entry.pageIndex, annotation)
        }
    }
}
