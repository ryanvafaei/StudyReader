import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import StudyReader

private struct RGBA {
    var red: Int
    var green: Int
    var blue: Int
    var alpha: Int
}

private struct DecodedPNG {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    /// Pixel at (x, y) counted from the top-left.
    func pixel(x: Int, y: Int) -> RGBA {
        let offset = (y * width + x) * 4
        return RGBA(red: Int(bytes[offset]), green: Int(bytes[offset + 1]),
                    blue: Int(bytes[offset + 2]), alpha: Int(bytes[offset + 3]))
    }

    init(url: URL) throws {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        #expect(drawn)
        self.width = width
        self.height = height
        bytes = buffer
    }
}

private func makeTemporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory
        .appending(path: "CoverTests", directoryHint: .isDirectory)
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

private func writePNG(width: Int, height: Int, to url: URL) throws {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
}

@Suite("Covers")
struct CoverTests {
    @Test
    func rendersFirstPage() throws {
        let source = try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.coloredRegion(), name: "colored.pdf")
        let destination = try makeTemporaryFolder().appending(path: "cover.png", directoryHint: .notDirectory)
        try CoverRenderer.renderPDFPage(fileAt: source, pageIndex: 0, to: destination)

        let png = try DecodedPNG(url: destination)
        #expect(png.height == 600)
        #expect(png.width == Int((612.0 / 792.0 * 600).rounded()))

        let scale = Double(png.height) / 792.0
        let rect = PDFFixtureBuilder.coloredRect
        let centerX = Int((rect.midX * scale).rounded())
        let centerY = png.height - Int((rect.midY * scale).rounded())
        let center = png.pixel(x: centerX, y: centerY)
        #expect(center.red > 200)
        #expect(center.green < 60)
        #expect(center.blue < 60)
        #expect(center.alpha == 255)

        let corner = png.pixel(x: 0, y: 0)
        #expect(corner.red > 250 && corner.green > 250 && corner.blue > 250)
        #expect(corner.alpha == 255)
    }

    @Test
    func rendersTheCropBoxAndPageRotation() throws {
        let cropped = try #require(PDFDocument(data: PDFFixtureBuilder.coloredRegion()))
        let croppedPage = try #require(cropped.page(at: 0))
        croppedPage.setBounds(PDFFixtureBuilder.coloredRect, for: .cropBox)
        let croppedURL = try PDFFixtureBuilder.writeTemporary(try #require(cropped.dataRepresentation()), name: "cropped.pdf")
        let folder = try makeTemporaryFolder()

        let croppedPNG = folder.appending(path: "cropped.png", directoryHint: .notDirectory)
        try CoverRenderer.renderPDFPage(fileAt: croppedURL, pageIndex: 0, to: croppedPNG)
        let croppedImage = try DecodedPNG(url: croppedPNG)
        #expect(croppedImage.width == 600)
        #expect(croppedImage.height == 450)
        for (x, y) in [(5, 5), (595, 5), (5, 445), (595, 445), (300, 225)] {
            let pixel = croppedImage.pixel(x: x, y: y)
            #expect(pixel.red > 200 && pixel.green < 60 && pixel.blue < 60)
        }

        let rotated = try #require(PDFDocument(data: PDFFixtureBuilder.coloredRegion()))
        try #require(rotated.page(at: 0)).rotation = 90
        let rotatedURL = try PDFFixtureBuilder.writeTemporary(try #require(rotated.dataRepresentation()), name: "rotated.pdf")
        let rotatedPNG = folder.appending(path: "rotated.png", directoryHint: .notDirectory)
        try CoverRenderer.renderPDFPage(fileAt: rotatedURL, pageIndex: 0, to: rotatedPNG)
        let rotatedImage = try DecodedPNG(url: rotatedPNG)
        #expect(rotatedImage.width == 600)
        #expect(rotatedImage.height == Int((612.0 / 792.0 * 600).rounded()))
        // A 90 degree clockwise turn moves page point (x, y) to (y, 612 - x) of the 792 x 612 display.
        let rect = PDFFixtureBuilder.coloredRect
        let scale = 600.0 / 792.0
        let turnedX = Int((rect.midY * scale).rounded())
        let turnedY = rotatedImage.height - Int(((612.0 - rect.midX) * scale).rounded())
        let turned = rotatedImage.pixel(x: turnedX, y: turnedY)
        #expect(turned.red > 200 && turned.green < 60 && turned.blue < 60)
        let corner = rotatedImage.pixel(x: 0, y: 0)
        #expect(corner.red > 250 && corner.green > 250 && corner.blue > 250)
    }

    @Test
    func convertsImage() throws {
        let folder = try makeTemporaryFolder()
        let source = folder.appending(path: "wide.png", directoryHint: .notDirectory)
        try writePNG(width: 1200, height: 300, to: source)
        let destination = folder.appending(path: "converted.png", directoryHint: .notDirectory)
        try CoverRenderer.convertImage(at: source, to: destination)

        let converted = try DecodedPNG(url: destination)
        #expect(converted.width == 600)
        #expect(converted.height == 150)
    }

    @Test
    func convertImageNeverUpscales() throws {
        let folder = try makeTemporaryFolder()
        let source = folder.appending(path: "small.png", directoryHint: .notDirectory)
        try writePNG(width: 200, height: 100, to: source)
        let destination = folder.appending(path: "converted.png", directoryHint: .notDirectory)
        try CoverRenderer.convertImage(at: source, to: destination)

        let converted = try DecodedPNG(url: destination)
        #expect(converted.width == 200)
        #expect(converted.height == 100)
    }

    @Test
    func convertImageRejectsNonImages() throws {
        let folder = try makeTemporaryFolder()
        let source = folder.appending(path: "notes.png", directoryHint: .notDirectory)
        try Data("not an image".utf8).write(to: source)
        let destination = folder.appending(path: "converted.png", directoryHint: .notDirectory)
        #expect(throws: CoverError.cannotOpen) {
            try CoverRenderer.convertImage(at: source, to: destination)
        }
    }

    @Test
    func pageOutOfRangeThrows() throws {
        let source = try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.coloredRegion(), name: "colored.pdf")
        let destination = try makeTemporaryFolder().appending(path: "cover.png", directoryHint: .notDirectory)
        #expect(throws: CoverError.pageOutOfRange) {
            try CoverRenderer.renderPDFPage(fileAt: source, pageIndex: 3, to: destination)
        }
        #expect(throws: CoverError.pageOutOfRange) {
            try CoverRenderer.renderPDFPage(fileAt: source, pageIndex: -1, to: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
    }

    @Test(.timeLimit(.minutes(1)))
    func coverServiceAppliesChanges() async throws {
        let env = try AppEnvironment.inMemory()
        defer { TestFileStore.remove(env.fileStore) }
        let store = env.fileStore
        let repository = env.documentRepository
        let service = CoverService(fileStore: store, documents: repository)

        let pdfId = UUID().uuidString
        try store.createDocumentFolder(documentId: pdfId)
        let original = try store.originalFileURL(documentId: pdfId, fileType: .pdf)
        try PDFFixtureBuilder.coloredRegion().write(to: original)
        try await repository.insert(TestData.document(id: pdfId, fileType: .pdf))
        let cover = try store.coverURL(documentId: pdfId)

        try await service.resetCover(documentId: pdfId)
        #expect(FileManager.default.fileExists(atPath: cover.path(percentEncoded: false)))
        var row = try #require(try await repository.fetch(id: pdfId))
        #expect(row.coverPath == "\(pdfId)/cover.png")
        #expect(row.coverSource == .automatic)
        let reset = try DecodedPNG(url: cover)
        #expect(reset.height == 600)

        let imageFolder = try makeTemporaryFolder()
        let customImage = imageFolder.appending(path: "custom.png", directoryHint: .notDirectory)
        try writePNG(width: 1200, height: 300, to: customImage)
        try await service.setCustomCover(documentId: pdfId, imageURL: customImage)
        row = try #require(try await repository.fetch(id: pdfId))
        #expect(row.coverPath == "\(pdfId)/cover.png")
        #expect(row.coverSource == .custom)
        let custom = try DecodedPNG(url: cover)
        #expect(custom.width == 600 && custom.height == 150)

        try await service.usePageAsCover(documentId: pdfId, pageIndex: 0)
        row = try #require(try await repository.fetch(id: pdfId))
        #expect(row.coverPath == "\(pdfId)/cover.png")
        #expect(row.coverSource == .page)
        #expect(try DecodedPNG(url: cover).height == 600)

        // A failed render keeps the old cover and the row.
        let before = try Data(contentsOf: cover)
        await #expect(throws: CoverError.pageOutOfRange) {
            try await service.usePageAsCover(documentId: pdfId, pageIndex: 9)
        }
        #expect(try Data(contentsOf: cover) == before)
        row = try #require(try await repository.fetch(id: pdfId))
        #expect(row.coverSource == .page)
        let leftovers = try FileManager.default.contentsOfDirectory(
            atPath: try store.documentFolderURL(documentId: pdfId).path(percentEncoded: false)
        ).sorted()
        #expect(leftovers == ["cover.png", "original.pdf"])

        // Markdown: reset removes cover.png and leaves coverPath nil.
        let markdownId = UUID().uuidString
        try store.createDocumentFolder(documentId: markdownId)
        let markdownCover = try store.coverURL(documentId: markdownId)
        try writePNG(width: 100, height: 100, to: markdownCover)
        var markdown = TestData.document(id: markdownId, fileType: .markdown)
        markdown.coverPath = "\(markdownId)/cover.png"
        markdown.coverSource = .custom
        try await repository.insert(markdown)

        try await service.resetCover(documentId: markdownId)
        #expect(!FileManager.default.fileExists(atPath: markdownCover.path(percentEncoded: false)))
        let markdownRow = try #require(try await repository.fetch(id: markdownId))
        #expect(markdownRow.coverPath == nil)
        #expect(markdownRow.coverSource == .automatic)

        try await service.resetCover(documentId: markdownId)
        let again = try #require(try await repository.fetch(id: markdownId))
        #expect(again.coverPath == nil)

        await #expect(throws: CoverError.cannotOpen) {
            try await service.usePageAsCover(documentId: markdownId, pageIndex: 0)
        }
        await #expect(throws: RepositoryError.notFound) {
            try await service.resetCover(documentId: UUID().uuidString)
        }
    }
}
