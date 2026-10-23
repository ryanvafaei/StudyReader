import Foundation
import Synchronization
@testable import StudyReader

/// Test clock. Thread-safe via `Mutex`; no `@unchecked Sendable`.
final class FixedNow: Now {
    private let date: Mutex<Date>

    init(_ date: Date) {
        self.date = Mutex(date)
    }

    func callAsFunction() -> Date {
        date.withLock { $0 }
    }

    func set(_ newDate: Date) {
        date.withLock { $0 = newDate }
    }

    func advance(by seconds: TimeInterval) {
        date.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}
