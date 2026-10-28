import AppKit
import Foundation
import ImageIO
import Testing
@testable import StudyReader

@Suite("SnapshotService")
struct SnapshotServiceTests {
    private struct Pixel {
        let red: Int
        let green: Int
        let blue: Int
    }

    private struct Bitmap {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        /// Row 0 is the top row.
        func pixel(x: Int, y: Int) -> Pixel {
            let offset = (y * width + x) * 4
            return Pixel(red: Int(bytes[offset]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset + 2]))
        }
    }

    private static func bitmap(fromPNG data: Data) throws -> Bitmap {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn)
        return Bitmap(width: width, height: height, bytes: bytes)
    }

    private static func isRed(_ pixel: Pixel) -> Bool {
        pixel.red > 200 && pixel.green < 60 && pixel.blue < 60
    }

    private static func isWhite(_ pixel: Pixel) -> Bool {
        pixel.red > 240 && pixel.green > 240 && pixel.blue > 240
    }

    private static func coloredRegionURL() throws -> URL {
        try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.coloredRegion(), name: "colored.pdf")
    }

    @Test
    func rendersRegion() throws {
        let url = try Self.coloredRegionURL()
        let data = try SnapshotService.renderPNG(fileAt: url, pageIndex: 0, rect: PDFFixtureBuilder.coloredRect)
        let bitmap = try Self.bitmap(fromPNG: data)
        #expect(bitmap.width == 400 && bitmap.height == 300, "size: \(bitmap.width) x \(bitmap.height)")
        let center = bitmap.pixel(x: 200, y: 150)
        #expect(Self.isRed(center), "center: \(center)")
        for (x, y) in [(3, 3), (bitmap.width - 4, 3), (3, bitmap.height - 4), (bitmap.width - 4, bitmap.height - 4)] {
            let corner = bitmap.pixel(x: x, y: y)
            #expect(Self.isRed(corner), "corner (\(x), \(y)): \(corner)")
        }
    }

    @Test @MainActor
    func capturesUninverted() throws {
        let url = try Self.coloredRegionURL()
        let rect = PDFFixtureBuilder.coloredRect.insetBy(dx: -20, dy: -20)

        func check(_ data: Data, _ label: String) throws {
            let bitmap = try Self.bitmap(fromPNG: data)
            #expect(bitmap.width == 480 && bitmap.height == 380, "\(label) size: \(bitmap.width) x \(bitmap.height)")
            let center = bitmap.pixel(x: 240, y: 190)
            #expect(Self.isRed(center), "\(label) center: \(center)")
            // The text line "Figure 1" lies in the bottom margin, so only the top and left margins are sampled.
            for (x, y) in [(5, 5), (bitmap.width - 6, 5), (240, 10), (10, 190)] {
                let margin = bitmap.pixel(x: x, y: y)
                #expect(Self.isWhite(margin), "\(label) margin (\(x), \(y)): \(margin)")
            }
        }

        let dark = try #require(NSAppearance(named: .darkAqua))
        var viaDrawingAppearance: Data?
        var renderError: (any Error)?
        dark.performAsCurrentDrawingAppearance {
            do {
                viaDrawingAppearance = try SnapshotService.renderPNG(fileAt: url, pageIndex: 0, rect: rect)
            } catch {
                renderError = error
            }
        }
        try #require(renderError == nil)
        try check(try #require(viaDrawingAppearance), "drawing appearance")

        let previous = NSApp.appearance
        NSApp.appearance = dark
        defer { NSApp.appearance = previous }
        try check(try SnapshotService.renderPNG(fileAt: url, pageIndex: 0, rect: rect), "app appearance")
    }

    @Test
    func clipsToPage() {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        #expect(SnapshotService.clippedRect(CGRect(x: -50, y: -50, width: 100, height: 100), pageBounds: page)
            == CGRect(x: 0, y: 0, width: 50, height: 50))
        #expect(SnapshotService.clippedRect(CGRect(x: 700, y: 100, width: 100, height: 100), pageBounds: page) == nil)
        #expect(SnapshotService.clippedRect(CGRect(x: 100, y: 100, width: 100, height: 100), pageBounds: page)
            == CGRect(x: 100, y: 100, width: 100, height: 100))
    }

    @Test
    func ignoresTinyRects() {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        #expect(SnapshotService.clippedRect(CGRect(x: 100, y: 100, width: 9, height: 50), pageBounds: page) == nil)
        #expect(SnapshotService.clippedRect(CGRect(x: 100, y: 100, width: 50, height: 9), pageBounds: page) == nil)
        #expect(SnapshotService.clippedRect(CGRect(x: 100, y: 100, width: 10, height: 10), pageBounds: page) != nil)
    }

    @Test
    func errors() throws {
        let url = try Self.coloredRegionURL()
        let rect = PDFFixtureBuilder.coloredRect
        #expect(throws: SnapshotError.pageOutOfRange) {
            try SnapshotService.renderPNG(fileAt: url, pageIndex: 5, rect: rect)
        }
        #expect(throws: SnapshotError.pageOutOfRange) {
            try SnapshotService.renderPNG(fileAt: url, pageIndex: -1, rect: rect)
        }
        #expect(throws: SnapshotError.emptyRect) {
            try SnapshotService.renderPNG(fileAt: url, pageIndex: 0, rect: CGRect(x: 2000, y: 2000, width: 50, height: 50))
        }
        let damaged = try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.damaged(), name: "damaged.pdf")
        #expect(throws: SnapshotError.cannotOpen) {
            try SnapshotService.renderPNG(fileAt: damaged, pageIndex: 0, rect: rect)
        }
    }

    @Test
    func pixelSizeIsCapped() {
        let normal = SnapshotService.pixelSize(for: CGSize(width: 100, height: 50))
        #expect(normal.width == 200 && normal.height == 100)

        let wide = SnapshotService.pixelSize(for: CGSize(width: 10_000, height: 10))
        #expect(wide.width <= SnapshotService.maximumPixelSide && wide.width > 0 && wide.height > 0, "wide: \(wide)")

        let tall = SnapshotService.pixelSize(for: CGSize(width: 10, height: 10_000))
        #expect(tall.height <= SnapshotService.maximumPixelSide && tall.width > 0 && tall.height > 0, "tall: \(tall)")

        let huge = SnapshotService.pixelSize(for: CGSize(width: 5000, height: 5000))
        #expect(huge.width * huge.height <= SnapshotService.maximumPixelCount, "huge: \(huge)")
        #expect(huge.width > 0 && huge.height > 0)

        let tiny = SnapshotService.pixelSize(for: CGSize(width: 0.2, height: 0.2))
        #expect(tiny.width == 1 && tiny.height == 1)
    }

    @Test
    func displayedRectFollowsRotation() {
        let crop = CGRect(x: 10, y: 20, width: 200, height: 100)
        let region = CGRect(x: 30, y: 40, width: 50, height: 20)
        #expect(SnapshotService.displayedRect(of: region, cropBox: crop, rotation: 0)
            == CGRect(x: 20, y: 20, width: 50, height: 20))
        // 90 degrees clockwise: the displayed page is 100 wide and 200 tall; (x, y) -> (y, width - x).
        #expect(SnapshotService.displayedRect(of: region, cropBox: crop, rotation: 90)
            == CGRect(x: 20, y: 130, width: 20, height: 50))
        #expect(SnapshotService.displayedRect(of: region, cropBox: crop, rotation: 180)
            == CGRect(x: 130, y: 60, width: 50, height: 20))
        #expect(SnapshotService.displayedRect(of: region, cropBox: crop, rotation: 270)
            == CGRect(x: 60, y: 20, width: 20, height: 50))
        #expect(SnapshotService.displayedRect(of: region, cropBox: crop, rotation: -90)
            == SnapshotService.displayedRect(of: region, cropBox: crop, rotation: 270))
    }
}
