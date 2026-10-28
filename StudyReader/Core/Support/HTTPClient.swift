import Foundation

/// Network access for logic. Logic sends requests only through an injected `HTTPClient` and never calls
/// `URLSession` itself (ARCHITECTURE §3, ADR-0018). `URLSessionHTTPClient` is the only implementation that does.
protocol HTTPClient: Sendable {
    /// Sends `request` and returns the body with the HTTP response. Transport failures throw (`URLError`).
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// `HTTPClient` over a `URLSession`. The default session is ephemeral: no cookies, cache or credentials on disk.
struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
