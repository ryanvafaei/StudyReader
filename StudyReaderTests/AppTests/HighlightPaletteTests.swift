import AppKit
import Testing
@testable import StudyReader

@MainActor
@Suite struct HighlightPaletteTests {
    @Test func swatchImageIsColouredAndNotTemplate() throws {
        for color in HighlightColor.allCases {
            let image = HighlightPalette.swatchImage(color)
            #expect(image.isTemplate == false, "\(color) swatch is a template image")
            #expect(image.size == NSSize(width: 12, height: 12), "\(color) swatch size is \(image.size)")

            let rep = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 24,
                pixelsHigh: 24,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ))
            let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            image.draw(in: NSRect(x: 0, y: 0, width: 24, height: 24))
            NSGraphicsContext.restoreGraphicsState()

            let pixel = try #require(rep.colorAt(x: 12, y: 12)?.usingColorSpace(.sRGB))
            let expected = try #require(HighlightPalette.nsColor(color).usingColorSpace(.sRGB))
            #expect(abs(pixel.redComponent - expected.redComponent) < 0.02, "\(color) red")
            #expect(abs(pixel.greenComponent - expected.greenComponent) < 0.02, "\(color) green")
            #expect(abs(pixel.blueComponent - expected.blueComponent) < 0.02, "\(color) blue")
        }
    }
}
