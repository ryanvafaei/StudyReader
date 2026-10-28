import Foundation
@testable import StudyReader

/// Answers requests from a queue of canned replies and records every request. Never touches the network.
actor StubHTTPClient: HTTPClient {
    enum Reply: Sendable {
        case response(status: Int, body: String)
        case failure(any Error)
    }

    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply] = []) {
        self.replies = replies
    }

    func enqueue(_ reply: Reply) {
        replies.append(reply)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else {
            throw URLError(.resourceUnavailable)
        }
        switch replies.removeFirst() {
        case .failure(let error):
            throw error
        case .response(let status, let body):
            guard let response = HTTPURLResponse(
                url: request.url ?? URL(filePath: "/"),
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            ) else {
                throw URLError(.badServerResponse)
            }
            return (Data(body.utf8), response)
        }
    }
}
