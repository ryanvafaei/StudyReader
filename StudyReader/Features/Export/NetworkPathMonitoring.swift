import Foundation
import Network

/// Whether the Mac can reach the network. The only seam over Network.framework (ADR-0018, T74).
protocol NetworkPathMonitoring: Sendable {
    /// Emits true when the path becomes satisfied, false when it becomes unsatisfied. First value = current state.
    /// Each call starts its own monitor; it stops when the stream's consumer stops.
    func pathUpdates() -> AsyncStream<Bool>
}

/// `NWPathMonitor` on its own dispatch queue.
struct SystemNetworkPathMonitor: NetworkPathMonitoring {
    init() {}

    func pathUpdates() -> AsyncStream<Bool> {
        AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in
                monitor.cancel()
            }
            monitor.start(queue: DispatchQueue(label: "com.ryanvafaei.StudyReader.network-path"))
        }
    }
}
