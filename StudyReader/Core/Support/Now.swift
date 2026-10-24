import Foundation

/// Injectable clock. Logic takes `Now` instead of calling `Date()` (ARCHITECTURE §3).
protocol Now: Sendable {
    func callAsFunction() -> Date
}

/// The only place in the app that calls `Date()`. Returns storage-rounded dates (ADR-0012).
struct SystemNow: Now {
    init() {}
    func callAsFunction() -> Date { Date().storageRounded }
}
