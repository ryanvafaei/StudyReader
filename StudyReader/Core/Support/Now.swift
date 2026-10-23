import Foundation

/// Injectable clock. Logic takes `Now` instead of calling `Date()` (ARCHITECTURE §3).
protocol Now: Sendable {
    func callAsFunction() -> Date
}

/// The only place in the app that calls `Date()`.
struct SystemNow: Now {
    init() {}
    func callAsFunction() -> Date { Date() }
}
