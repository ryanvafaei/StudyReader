import Foundation
import Testing
@testable import StudyReader

@Suite("DriveUploadRequest")
struct DriveUploadRequestTests {
    private static let boundary = "studyreader-boundary"

    private func body(_ request: URLRequest) -> String {
        String(decoding: request.httpBody ?? Data(), as: UTF8.self)
    }

    private func make(
        fileId: String? = nil,
        folderId: String? = nil,
        format: ExportFormat = .markdown,
        content: String = "# Hello"
    ) throws -> URLRequest {
        try DriveUploadRequest.make(
            fileId: fileId,
            title: "StudyReader – All highlights",
            folderId: folderId,
            format: format,
            content: content,
            accessToken: "tok",
            boundary: Self.boundary
        )
    }

    @Test func createWithoutFolder() throws {
        let request = try make()
        #expect(request.httpMethod == "POST")
        #expect(
            request.url?.absoluteString
                == "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink"
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/related; boundary=studyreader-boundary")
        let expected = [
            "--studyreader-boundary",
            "Content-Type: application/json; charset=UTF-8",
            "",
            #"{"mimeType":"application/vnd.google-apps.document","name":"StudyReader – All highlights"}"#,
            "--studyreader-boundary",
            "Content-Type: text/markdown; charset=UTF-8",
            "",
            "# Hello",
            "--studyreader-boundary--",
        ].joined(separator: "\r\n")
        #expect(body(request) == expected)
    }

    @Test func createWithFolder() throws {
        let request = try make(folderId: "FOLDER123")
        #expect(
            body(request).contains(
                #"{"mimeType":"application/vnd.google-apps.document","name":"StudyReader – All highlights","parents":["FOLDER123"]}"#
            )
        )
    }

    @Test func updateReplacesSameFile() throws {
        let request = try make(fileId: "FILE1", folderId: "FOLDER123", content: "new")
        #expect(request.httpMethod == "PATCH")
        #expect(
            request.url?.absoluteString
                == "https://www.googleapis.com/upload/drive/v3/files/FILE1?uploadType=multipart&fields=id,modifiedTime"
        )
        let expected = [
            "--studyreader-boundary",
            "Content-Type: application/json; charset=UTF-8",
            "",
            #"{"name":"StudyReader – All highlights"}"#,
            "--studyreader-boundary",
            "Content-Type: text/markdown; charset=UTF-8",
            "",
            "new",
            "--studyreader-boundary--",
        ].joined(separator: "\r\n")
        #expect(body(request) == expected)
    }

    @Test func htmlContentType() throws {
        let create = try make(format: .html, content: "<h1>Hi</h1>")
        #expect(body(create).contains("Content-Type: text/html; charset=UTF-8\r\n\r\n<h1>Hi</h1>\r\n--studyreader-boundary--"))
        let update = try make(fileId: "FILE1", format: .html, content: "<h1>Hi</h1>")
        #expect(body(update).contains("Content-Type: text/html; charset=UTF-8\r\n\r\n<h1>Hi</h1>"))
    }

    @Test func titleIsJSONEncoded() throws {
        let request = try DriveUploadRequest.make(
            fileId: nil,
            title: "Say \"hi\"\nand \\ go",
            folderId: nil,
            format: .markdown,
            content: "x",
            accessToken: "tok",
            boundary: Self.boundary
        )
        #expect(body(request).contains(#""name":"Say \"hi\"\nand \\ go""#))
    }

    @Test func fileIdIsPercentEncodedInPath() throws {
        let request = try make(fileId: "a/b?c")
        #expect(request.url?.path(percentEncoded: true) == "/upload/drive/v3/files/a%2Fb%3Fc")
        #expect(request.url?.query() == "uploadType=multipart&fields=id,modifiedTime")
    }

    @Test func randomBoundaryDiffersAndMatchesHeader() throws {
        let first = try make(content: "x")
        let again = try DriveUploadRequest.make(
            fileId: nil, title: "t", folderId: nil, format: .markdown, content: "x", accessToken: "tok"
        )
        let header = try #require(again.value(forHTTPHeaderField: "Content-Type"))
        let boundary = try #require(header.split(separator: "boundary=").last.map(String.init))
        #expect(body(again).hasPrefix("--\(boundary)\r\n"))
        #expect(body(again).hasSuffix("\r\n--\(boundary)--"))
        #expect(header != first.value(forHTTPHeaderField: "Content-Type"))
    }

    @Test func folderRequests() throws {
        let get = try DriveUploadRequest.folder(id: "APPFOLDER", accessToken: "tok")
        #expect(get.httpMethod == "GET")
        #expect(
            get.url?.absoluteString
                == "https://www.googleapis.com/drive/v3/files/APPFOLDER?fields=id,mimeType,trashed"
        )
        #expect(get.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(get.httpBody == nil)

        let odd = try DriveUploadRequest.folder(id: "a/b?c", accessToken: "tok")
        #expect(odd.url?.path(percentEncoded: true) == "/drive/v3/files/a%2Fb%3Fc")
        #expect(odd.url?.query() == "fields=id,mimeType,trashed")

        let find = try DriveUploadRequest.findAppFolder(accessToken: "tok")
        #expect(find.httpMethod == "GET")
        #expect(find.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(find.httpBody == nil)
        let url = try #require(find.url)
        #expect(url.path() == "/drive/v3/files")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.map(\.name) == ["q", "spaces", "orderBy", "pageSize", "fields"])
        #expect(
            items.first?.value
                == "name = 'StudyReader' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
        )
        #expect(items.dropFirst().map(\.value) == ["drive", "createdTime", "1", "files(id)"])

        let create = try DriveUploadRequest.createAppFolder(accessToken: "tok")
        #expect(create.httpMethod == "POST")
        #expect(create.url?.absoluteString == "https://www.googleapis.com/drive/v3/files?fields=id")
        #expect(create.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(create.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=UTF-8")
        #expect(body(create) == #"{"mimeType":"application/vnd.google-apps.folder","name":"StudyReader"}"#)
    }

    @Test func importFormatsRequest() throws {
        let request = try DriveUploadRequest.importFormats(accessToken: "tok")
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://www.googleapis.com/drive/v3/about?fields=importFormats")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.httpBody == nil)
    }
}
