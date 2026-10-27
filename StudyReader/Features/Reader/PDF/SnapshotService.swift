import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum SnapshotError: Error, Equatable {
    case cannotOpen, pageOutOfRange, emptyRect, encodeFailed
}

/// Renders a region of a PDF page into PNG data (SPEC F-08, ARCHITECTURE §5.4). It renders from its own
/// `PDFDocument` straight from the `PDFPage`, never from a view or the screen, so the result is the page as printed:
/// the dark-mode inversion of the PDF view and the app appearance never reach it.
enum SnapshotService {
    static let scale: CGFloat = 2
    static let minimumSide: CGFloat = 10

    /// `rect` ∩ `pageBounds`; nil if the result is narrower or shorter than `minimumSide` or `rect` isn't finite.
    static func clippedRect(_ rect: CGRect, pageBounds: CGRect) -> CGRect? {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite else {
            return nil
        }
        let clipped = rect.standardized.intersection(pageBounds)
        guard !clipped.isNull, clipped.width >= minimumSide, clipped.height >= minimumSide else { return nil }
        return clipped
    }

    /// Opens its own `PDFDocument(url:)` (call off the main actor). Renders page `pageIndex`, cropped to `rect`
    /// (page space, the same space as `PDFPage.bounds(for:)`), at `scale` on opaque white, and returns PNG data.
    /// The part of `rect` outside the crop box is dropped.
    static func renderPNG(fileAt url: URL, pageIndex: Int, rect: CGRect) throws -> Data {
        guard let document = PDFDocument(url: url) else { throw SnapshotError.cannotOpen }
        if document.isLocked, !document.unlock(withPassword: "") { throw SnapshotError.cannotOpen }
        guard pageIndex >= 0, pageIndex < document.pageCount, let page = document.page(at: pageIndex) else {
            throw SnapshotError.pageOutOfRange
        }
        let cropBox = page.bounds(for: .cropBox)
        let region = rect.standardized.intersection(cropBox)
        guard rect.width.isFinite, rect.height.isFinite, !region.isNull, !region.isEmpty else {
            throw SnapshotError.emptyRect
        }
        let displayed = displayedRect(of: region, cropBox: cropBox, rotation: page.rotation)

        let width = max(Int((displayed.width * scale).rounded()), 1)
        let height = max(Int((displayed.height * scale).rounded()), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SnapshotError.encodeFailed
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: CGFloat(width) / displayed.width, y: CGFloat(height) / displayed.height)
        context.translateBy(x: -displayed.minX, y: -displayed.minY)
        page.draw(with: .cropBox, to: context)

        guard let image = context.makeImage() else { throw SnapshotError.encodeFailed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw SnapshotError.encodeFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw SnapshotError.encodeFailed }
        return data as Data
    }

    /// `region` (unrotated page space, inside `cropBox`) in the space `PDFPage.draw(with:to:)` draws in: origin at the
    /// bottom-left of the crop box as displayed, so for a page rotated clockwise by `rotation` degrees the corners
    /// move with it and width and height swap for 90 and 270.
    static func displayedRect(of region: CGRect, cropBox: CGRect, rotation: Int) -> CGRect {
        let turns = ((rotation % 360) + 360) % 360
        func map(_ point: CGPoint) -> CGPoint {
            let x = point.x - cropBox.minX
            let y = point.y - cropBox.minY
            switch turns {
            case 90: return CGPoint(x: y, y: cropBox.width - x)
            case 180: return CGPoint(x: cropBox.width - x, y: cropBox.height - y)
            case 270: return CGPoint(x: cropBox.height - y, y: x)
            default: return CGPoint(x: x, y: y)
            }
        }
        let first = map(CGPoint(x: region.minX, y: region.minY))
        let second = map(CGPoint(x: region.maxX, y: region.maxY))
        return CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(first.x - second.x),
            height: abs(first.y - second.y)
        )
    }
}
