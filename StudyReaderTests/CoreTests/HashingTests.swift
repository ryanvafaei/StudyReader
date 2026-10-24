import Foundation
import Testing
@testable import StudyReader

@Suite struct HashingTests {
    @Test func knownVectors() {
        #expect(Hashing.sha256Hex(of: "abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(Hashing.sha256Hex(of: Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func fileMatchesData() throws {
        let count = 3 * 1024 * 1024 + 17
        let data = Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ ($0 >> 8)) })
        let url = FileManager.default.temporaryDirectory
            .appending(path: "HashingTests-\(UUID().uuidString).bin")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let fromFile = try Hashing.sha256Hex(ofFileAt: url)
        #expect(fromFile == Hashing.sha256Hex(of: data))
        #expect(fromFile.count == 64)
    }

    @Test func missingFileThrows() {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "HashingTests-missing-\(UUID().uuidString).bin")
        #expect(throws: (any Error).self) {
            try Hashing.sha256Hex(ofFileAt: url)
        }
    }
}
