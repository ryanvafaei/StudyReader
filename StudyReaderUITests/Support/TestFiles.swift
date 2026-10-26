import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

enum TestFileError: Error {
    case cannotCreate(URL)
}

/// Files the UI tests import or pick, written to a fresh temporary folder.
@MainActor
enum TestFiles {
    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "StudyReaderUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// One-page US Letter PDF named "<title>.pdf" whose first line is `title`.
    static func pdf(_ title: String, in folder: URL) throws -> URL {
        let url = folder.appending(path: "\(title).pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw TestFileError.cannotCreate(url)
        }
        context.beginPDFPage(nil)
        let text = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 24)])
        context.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        context.endPDFPage()
        context.closePDF()
        return url
    }

    /// Solid red 300×400 PNG, easy to recognise in a cover.
    static func redPNG(in folder: URL) throws -> URL {
        let url = folder.appending(path: "red-cover.png")
        guard let context = CGContext(
            data: nil,
            width: 300,
            height: 400,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestFileError.cannotCreate(url)
        }
        context.setFillColor(CGColor(red: 0.86, green: 0.16, blue: 0.16, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw TestFileError.cannotCreate(url)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw TestFileError.cannotCreate(url) }
        return url
    }
}
