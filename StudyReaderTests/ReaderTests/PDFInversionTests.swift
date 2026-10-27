import AppKit
import CoreImage
import Foundation
import Testing
@testable import StudyReader

@Suite("PDFInversion")
struct PDFInversionTests {
    @Test
    func decision() throws {
        let dark = try #require(NSAppearance(named: .darkAqua))
        let light = try #require(NSAppearance(named: .aqua))
        #expect(PDFInversion.shouldInvert(appearance: dark, settingEnabled: true))
        #expect(!PDFInversion.shouldInvert(appearance: dark, settingEnabled: false))
        #expect(!PDFInversion.shouldInvert(appearance: light, settingEnabled: true))
        #expect(!PDFInversion.shouldInvert(appearance: light, settingEnabled: false))
    }

    @Test
    func hueIsPreserved() throws {
        let red = try Self.filteredPixel(red: 1, green: 0, blue: 0)
        #expect(red.r > red.g)
        #expect(red.r > red.b)
        let white = try Self.filteredPixel(red: 1, green: 1, blue: 1)
        #expect(white.r < 0.05)
        #expect(white.g < 0.05)
        #expect(white.b < 0.05)
    }

    /// Runs a 1 x 1 image of the color through `PDFInversion.filters()` and reads it back as sRGB, 0...1 per channel.
    private static func filteredPixel(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> (r: Double, g: Double, b: Double) {
        let bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        var image = CIImage(color: CIColor(red: red, green: green, blue: blue)).cropped(to: bounds)
        for filter in PDFInversion.filters() {
            filter.setValue(image, forKey: kCIInputImageKey)
            image = try #require(filter.outputImage)
        }
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = CIContext(options: [.workingColorSpace: colorSpace, .outputColorSpace: colorSpace])
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &pixel, rowBytes: 4, bounds: bounds, format: .RGBA8, colorSpace: colorSpace)
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }
}
