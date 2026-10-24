import Foundation
import PDFKit
import Testing
@testable import StudyReader

@Suite("PDFImportInspector")
struct PDFImportInspectorTests {
    private static func fixture(_ data: Data, name: String = "fixture.pdf") throws -> URL {
        try PDFFixtureBuilder.writeTemporary(data, name: name)
    }

    @Test
    func readsMetadataAndPageCount() throws {
        let withMetadata = try Self.fixture(PDFFixtureBuilder.withMetadata(title: "Neural Networks", author: "Ada Lovelace"))
        #expect(PDFImportInspector.inspect(fileAt: withMetadata, password: nil) == .ok(PDFInfo(
            pageCount: 1,
            title: "Neural Networks",
            author: "Ada Lovelace",
            isEncrypted: false
        )))

        let multiPage = try Self.fixture(PDFFixtureBuilder.plainMultiPage(pageCount: 5))
        guard case let .ok(info) = PDFImportInspector.inspect(fileAt: multiPage, password: nil) else {
            Issue.record("plainMultiPage should inspect as .ok")
            return
        }
        #expect(info.pageCount == 5)
        #expect(info.isEncrypted == false)
    }

    @Test
    func detectsDamaged() throws {
        let url = try Self.fixture(PDFFixtureBuilder.damaged())
        #expect(PDFImportInspector.inspect(fileAt: url, password: nil) == .damaged)
    }

    @Test
    func locksAndUnlocksEncrypted() throws {
        let url = try Self.fixture(PDFFixtureBuilder.encrypted(password: "secret"))
        #expect(PDFImportInspector.inspect(fileAt: url, password: nil) == .locked)
        #expect(PDFImportInspector.inspect(fileAt: url, password: "wrong") == .locked)
        guard case let .ok(info) = PDFImportInspector.inspect(fileAt: url, password: "secret") else {
            Issue.record("the right password should inspect as .ok")
            return
        }
        #expect(info.isEncrypted == true)
        #expect(info.pageCount == 1)
    }

    @Test
    func writesUnlockedCopy() throws {
        let source = try Self.fixture(PDFFixtureBuilder.encrypted(password: "secret"))
        let before = try Data(contentsOf: source)
        let destination = source.deletingLastPathComponent().appending(path: "unlocked.pdf", directoryHint: .notDirectory)

        try PDFImportInspector.writeUnlockedCopy(of: source, password: "secret", to: destination)

        let copy = try #require(PDFDocument(url: destination))
        #expect(copy.isLocked == false)
        #expect(copy.pageCount == 1)
        #expect(copy.page(at: 0)?.string?.contains("Encrypted fixture") == true)
        #expect(try Data(contentsOf: source) == before)
        guard case .ok = PDFImportInspector.inspect(fileAt: destination, password: nil) else {
            Issue.record("the unlocked copy should inspect as .ok without a password")
            return
        }

        let wrong = source.deletingLastPathComponent().appending(path: "wrong.pdf", directoryHint: .notDirectory)
        #expect(throws: PDFImportError.locked) {
            try PDFImportInspector.writeUnlockedCopy(of: source, password: "wrong", to: wrong)
        }
        #expect(!FileManager.default.fileExists(atPath: wrong.path(percentEncoded: false)))
    }

    @Test
    func neverWritesToTheSourceFile() throws {
        let source = try Self.fixture(PDFFixtureBuilder.encrypted(password: "secret"))
        let before = try Data(contentsOf: source)
        #expect(throws: PDFImportError.writeFailed) {
            try PDFImportInspector.writeUnlockedCopy(of: source, password: "secret", to: source)
        }
        #expect(try Data(contentsOf: source) == before)

        let damaged = try Self.fixture(PDFFixtureBuilder.damaged())
        let destination = damaged.deletingLastPathComponent().appending(path: "out.pdf", directoryHint: .notDirectory)
        #expect(throws: PDFImportError.writeFailed) {
            try PDFImportInspector.writeUnlockedCopy(of: damaged, password: "secret", to: destination)
        }
    }
}
