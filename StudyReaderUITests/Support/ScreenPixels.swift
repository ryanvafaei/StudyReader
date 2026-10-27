import AppKit
import XCTest

/// Reads screen pixels for checks a query can't make: a cover's colour, whether part of a cover is sharp or blurred,
/// whether a menu swatch is coloured. Rects are screen points with a top-left origin, like `XCUIElement.frame`, on the
/// main display.
@MainActor
enum ScreenPixels {
    struct Stats {
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        /// 2nd and 98th percentile, so a few anti-aliased pixels don't decide the result.
        var lowLuminance = 0.0
        var highLuminance = 0.0
        var maxSaturation = 0.0

        var luminanceRange: Double { highLuminance - lowLuminance }
        var isMostlyRed: Bool { red > 0.6 && green < 0.4 && blue < 0.4 }
    }

    static func stats(of rect: CGRect) -> Stats? {
        let screenshot = XCUIScreen.main.screenshot()
        guard let image = screenshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let screen = NSScreen.screens.first,
              screen.frame.width > 0
        else { return nil }
        let scale = Double(image.width) / screen.frame.width
        let pixelRect = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral
        guard let cropped = image.cropping(to: pixelRect), cropped.width > 0, cropped.height > 0 else { return nil }

        let width = cropped.width
        let height = cropped.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        let count = width * height
        var stats = Stats()
        var luminances: [Double] = []
        luminances.reserveCapacity(count)
        var sums = (red: 0.0, green: 0.0, blue: 0.0)
        for pixel in 0..<count {
            let red = Double(bytes[pixel * 4]) / 255
            let green = Double(bytes[pixel * 4 + 1]) / 255
            let blue = Double(bytes[pixel * 4 + 2]) / 255
            sums.red += red
            sums.green += green
            sums.blue += blue
            luminances.append(0.2126 * red + 0.7152 * green + 0.0722 * blue)
            let high = max(red, green, blue)
            let low = min(red, green, blue)
            if high > 0.15 {
                stats.maxSaturation = max(stats.maxSaturation, (high - low) / high)
            }
        }
        luminances.sort()
        stats.lowLuminance = luminances[count * 2 / 100]
        stats.highLuminance = luminances[min(count - 1, count * 98 / 100)]
        stats.red = sums.red / Double(count)
        stats.green = sums.green / Double(count)
        stats.blue = sums.blue / Double(count)
        return stats
    }

    /// Number of pixels in `rect` whose red, green and blue are each within `tolerance` (0...1) of `color`.
    /// Returns nil when the screen can't be read.
    static func count(near color: (red: Double, green: Double, blue: Double), tolerance: Double, in rect: CGRect) -> Int? {
        let screenshot = XCUIScreen.main.screenshot()
        guard let image = screenshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let screen = NSScreen.screens.first,
              screen.frame.width > 0
        else { return nil }
        let scale = Double(image.width) / screen.frame.width
        let pixelRect = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral
        guard let cropped = image.cropping(to: pixelRect), cropped.width > 0, cropped.height > 0 else { return nil }
        let width = cropped.width
        let height = cropped.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var matches = 0
        for pixel in 0..<(width * height) {
            let red = Double(bytes[pixel * 4]) / 255
            let green = Double(bytes[pixel * 4 + 1]) / 255
            let blue = Double(bytes[pixel * 4 + 2]) / 255
            if abs(red - color.red) <= tolerance, abs(green - color.green) <= tolerance, abs(blue - color.blue) <= tolerance {
                matches += 1
            }
        }
        return matches
    }

    /// Attaches a crop of the main display, for the ui-tester's visual review.
    static func attach(_ rect: CGRect, named name: String, to testCase: XCTestCase) {
        let screenshot = XCUIScreen.main.screenshot()
        guard let image = screenshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let screen = NSScreen.screens.first,
              screen.frame.width > 0
        else { return }
        let scale = Double(image.width) / screen.frame.width
        let pixelRect = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        guard let cropped = image.cropping(to: pixelRect.integral) else { return }
        let attachment = XCTAttachment(image: NSImage(cgImage: cropped, size: rect.size))
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }
}
