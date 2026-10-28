import Foundation

/// Builds the Google Drive requests of ARCHITECTURE §9.2. Pure: no network, no clock.
enum DriveUploadRequest {
    static let documentMimeType = "application/vnd.google-apps.document"

    enum BuildError: Error, Equatable {
        case invalidURL
        case invalidMetadata
    }

    /// `POST …/files` (create, converting to a Google Doc) when `fileId` is nil, else `PATCH …/files/{fileId}`
    /// (replaces the content of that Doc). The body is `multipart/related` with CRLF line endings:
    /// a JSON metadata part, then the content part (`text/markdown` or `text/html`).
    /// `boundary` is injectable for tests; by default a random one that occurs in neither part.
    static func make(
        fileId: String?,
        title: String,
        folderId: String?,
        format: ExportFormat,
        content: String,
        accessToken: String,
        boundary: String? = nil
    ) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        if let fileId {
            components.percentEncodedPath = "/upload/drive/v3/files/" + encodePathSegment(fileId)
            components.percentEncodedQuery = "uploadType=multipart&fields=id,modifiedTime"
        } else {
            components.percentEncodedPath = "/upload/drive/v3/files"
            components.percentEncodedQuery = "uploadType=multipart&fields=id,webViewLink"
        }
        guard let url = components.url else { throw BuildError.invalidURL }

        let metadata = try metadataJSON(
            Metadata(
                name: title,
                mimeType: fileId == nil ? documentMimeType : nil,
                parents: fileId == nil ? folderId.map { [$0] } : nil
            )
        )
        let mediaType = format == .html ? "text/html" : "text/markdown"
        let usedBoundary = boundary ?? randomBoundary(avoiding: [metadata, content])

        var body = Data()
        body.append(Data("--\(usedBoundary)\r\n".utf8))
        body.append(Data("Content-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
        body.append(Data(metadata.utf8))
        body.append(Data("\r\n--\(usedBoundary)\r\n".utf8))
        body.append(Data("Content-Type: \(mediaType); charset=UTF-8\r\n\r\n".utf8))
        body.append(Data(content.utf8))
        body.append(Data("\r\n--\(usedBoundary)--".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = fileId == nil ? "POST" : "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(usedBoundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    /// `GET …/drive/v3/about?fields=importFormats`.
    static func importFormats(accessToken: String) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.percentEncodedPath = "/drive/v3/about"
        components.percentEncodedQuery = "fields=importFormats"
        guard let url = components.url else { throw BuildError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: Helpers

    private struct Metadata: Encodable {
        var name: String
        var mimeType: String?
        var parents: [String]?
    }

    private static func metadataJSON(_ metadata: Metadata) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(metadata)
        guard let json = String(data: data, encoding: .utf8) else { throw BuildError.invalidMetadata }
        return json
    }

    /// Unreserved characters only: a "/" or "?" in an ID can't change the path or start a query.
    private static func encodePathSegment(_ segment: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private static func randomBoundary(avoiding parts: [String]) -> String {
        while true {
            let candidate = "studyreader-" + UUID().uuidString
            if !parts.contains(where: { $0.contains(candidate) }) { return candidate }
        }
    }
}
