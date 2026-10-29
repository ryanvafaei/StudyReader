import Foundation
import Synchronization
@testable import StudyReader

/// Records every call so tests can check order. `grants` decides the permission answer.
final class StubNotificationCenter: ReminderNotificationCenter {
    enum Call: Equatable {
        case requestAuthorization
        case removePending(String)
        case scheduleDaily(identifier: String, hour: Int, minute: Int)
    }

    private let recorded = Mutex<[Call]>([])
    private let grants: Bool

    init(grants: Bool = true) {
        self.grants = grants
    }

    var calls: [Call] {
        recorded.withLock { $0 }
    }

    func requestAuthorization() async throws -> Bool {
        recorded.withLock { $0.append(.requestAuthorization) }
        return grants
    }

    func scheduleDaily(identifier: String, hour: Int, minute: Int, title: String, body: String) async throws {
        recorded.withLock { $0.append(.scheduleDaily(identifier: identifier, hour: hour, minute: minute)) }
    }

    func removePending(identifier: String) async {
        recorded.withLock { $0.append(.removePending(identifier)) }
    }
}
