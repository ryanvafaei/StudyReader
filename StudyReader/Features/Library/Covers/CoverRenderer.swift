import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum CoverError: Error, Equatable {
    case cannotOpen
    case pageOutOfRange
    case cannotEncode
}

/// Cover PNGs (SPEC F-11, ADR-0016). Synchronous; callers run it off the main actor. Each call opens its own
/// `PDFDocument`, and no PDFKit object leaves this type (ARCHITECTURE §3).
enum CoverRenderer {
    static let maxPixelSize = 600

    /// Renders the page (crop box) on opaque white, uninverted, scaled so the longest side is `maxPixelSize` px,
    /// with `PDFPage.draw(with: .cropBox, to:)`, and writes a PNG to `destination`.
    static func renderPDFPage(fileAt url: URL, pageIndex: Int, to destination: URL) throws {
        guard let document = PDFDocument(url: url), !document.isLocked else { throw CoverError.cannotOpen }
        guard pageIndex >= 0, pageIndex < document.pageCount, let page = document.page(at: pageIndex) else {
            throw CoverError.pageOutOfRange
        }
        let box = page.bounds(for: .cropBox)
        let isSideways = abs(page.rotation) % 180 == 90
        let displayWidth = Double(isSideways ? box.height : box.width)
        let displayHeight = Double(isSideways ? box.width : box.height)
        let size = pixelSize(width: displayWidth, height: displayHeight)
        guard let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw CoverError.cannotEncode }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        context.interpolationQuality = .high
        context.scaleBy(x: Double(size.width) / displayWidth, y: Double(size.height) / displayHeight)
        page.draw(with: .cropBox, to: context)

        guard let image = context.makeImage() else { throw CoverError.cannotEncode }
        try writePNG(image, to: destination)
    }

    /// Any ImageIO-readable image to PNG at `destination`, longest side at most `maxPixelSize` (downscale only).
    static func convertImage(at source: URL, to destination: URL) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0
        else { throw CoverError.cannotOpen }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), maxPixelSize),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw CoverError.cannotOpen
        }
        try writePNG(image, to: destination)
    }

    /// Pixel size with the longest side `maxPixelSize` and the aspect ratio kept (each side at least 1).
    static func pixelSize(width: Double, height: Double) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (maxPixelSize, maxPixelSize) }
        let scale = Double(maxPixelSize) / max(width, height)
        return (max(1, Int((width * scale).rounded())), max(1, Int((height * scale).rounded())))
    }

    private static func writePNG(_ image: CGImage, to destination: URL) throws {
        guard let target = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw CoverError.cannotEncode }
        CGImageDestinationAddImage(target, image, nil)
        guard CGImageDestinationFinalize(target) else { throw CoverError.cannotEncode }
    }
}
