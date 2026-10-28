import Foundation
@testable import StudyReader

/// Holds every request until `open()` is called, then answers from a `StubHTTPClient`. Lets a test keep an export in flight.
actor GatedHTTPClient: HTTPClient {
    private let inner: StubHTTPClient
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var arrivedCount = 0

    init(_ replies: [StubHTTPClient.Reply] = []) {
        inner = StubHTTPClient(replies)
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume() }
    }

    /// Requests that reached the client, held or answered.
    var requestCount: Int { arrivedCount }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        arrivedCount += 1
        if !isOpen {
            await withCheckedContinuation { waiters.append($0) }
        }
        return try await inner.send(request)
    }
}
