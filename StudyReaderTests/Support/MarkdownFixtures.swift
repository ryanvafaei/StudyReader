import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum MarkdownFixtureError: Error { case missing(String) }

enum MarkdownFixtures {
    /// Bundle(for: BundleToken.self).url(forResource: name, withExtension: "md", subdirectory: "Fixtures/markdown")
    /// Throws .missing(name) if not found. `name` has no extension, e.g. "all-elements".
    static func url(_ name: String) throws -> URL {
        guard let url = Bundle(for: BundleToken.self).url(
            forResource: name,
            withExtension: "md",
            subdirectory: "Fixtures/markdown"
        ) else {
            throw MarkdownFixtureError.missing(name)
        }
        return url
    }

    static func string(_ name: String) throws -> String {
        try String(contentsOf: url(name), encoding: .utf8)
    }

    /// Creates FileManager.default.temporaryDirectory/MarkdownFixtures/<UUID>/ containing:
    ///   notes.md          = contents of all-elements.md
    ///   images/diagram.png = 8×8 solid red PNG generated with CGContext + CGImageDestination (ImageIO, UTType.png)
    /// (images/missing.png is intentionally absent.) Returns the URL of notes.md.
    static func makeFolderWithImages() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "MarkdownFixtures", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let imagesFolder = folder.appending(path: "images", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)

        let notes = folder.appending(path: "notes.md")
        try FileManager.default.copyItem(at: url("all-elements"), to: notes)
        try writeRedPNG(to: imagesFolder.appending(path: "diagram.png"))
        return notes
    }

    private static func writeRedPNG(to destination: URL) throws {
        let size = 8
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = context.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard let imageDestination = CGImageDestinationCreateWithURL(
            destination as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(imageDestination, image, nil)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

private final class BundleToken {}
