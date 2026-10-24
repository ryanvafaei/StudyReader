import CryptoKit
import Foundation

/// SHA-256 helpers for import dedupe (F-02). Output is lowercase hex, 64 characters.
enum Hashing {
    /// Streams the file through SHA-256 in 1 MiB chunks, so large PDFs never load fully into memory.
    static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }

    /// Lowercase hex SHA-256 of `data`.
    static func sha256Hex(of data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    /// Lowercase hex SHA-256 of `string.utf8`.
    static func sha256Hex(of string: String) -> String {
        sha256Hex(of: Data(string.utf8))
    }

    private static let chunkSize = 1 << 20

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.reduce(into: "") { $0 += String(format: "%02x", $1) }
    }
}
