import Foundation
@testable import StudyReader

/// A network path the test controls: `emit(_:)` pushes a reachability change. One consumer; values emitted before
/// `pathUpdates()` is called are kept.
struct StubNetworkPath: NetworkPathMonitoring {
    private let stream: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
    }

    func pathUpdates() -> AsyncStream<Bool> {
        stream
    }

    func emit(_ satisfied: Bool) {
        continuation.yield(satisfied)
    }
}
