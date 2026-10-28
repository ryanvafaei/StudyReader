import Foundation

/// Drive's reason for a refused request, from the JSON error body (ARCHITECTURE §9.2, ADR-0018 amendment "M1/M2").
/// Pure. The body is decoded only to find the reason: it is never logged and never shown.
///
/// The reason is the first `error.errors[i].reason` that is one of the known values below, else the first one present
/// (always `.other`), else none (`.other`).
enum DriveErrorReason: Equatable, Sendable {
    /// `rateLimitExceeded`, `userRateLimitExceeded`: retried with backoff like a 429.
    case rateLimited
    /// `dailyLimitExceeded`
    case dailyLimit
    /// `storageQuotaExceeded`
    case storageFull
    /// `appNotAuthorizedToFile`, `insufficientFilePermissions`
    case noAccess
    /// Any other reason, no reason, or a body that isn't Drive's JSON.
    case other

    private struct Body: Decodable {
        struct Detail: Decodable {
            var errors: [Item]?
        }

        struct Item: Decodable {
            var reason: String?
        }

        var error: Detail?
    }

    static func parse(_ body: Data) -> DriveErrorReason {
        guard let decoded = try? JSONDecoder().decode(Body.self, from: body) else { return .other }
        let reasons = (decoded.error?.errors ?? []).compactMap(\.reason)
        for reason in reasons {
            if let known = known(reason) { return known }
        }
        return .other
    }

    private static func known(_ reason: String) -> DriveErrorReason? {
        switch reason {
        case "rateLimitExceeded", "userRateLimitExceeded": .rateLimited
        case "dailyLimitExceeded": .dailyLimit
        case "storageQuotaExceeded": .storageFull
        case "appNotAuthorizedToFile", "insufficientFilePermissions": .noAccess
        default: nil
        }
    }

    /// The name for logs: Drive's reason name where one reason maps to the case, else the case's category
    /// ("noAccess" covers two reasons). "other" for everything unknown. Never part of a response body.
    var logName: String {
        switch self {
        case .rateLimited: "rateLimitExceeded"
        case .dailyLimit: "dailyLimitExceeded"
        case .storageFull: "storageQuotaExceeded"
        case .noAccess: "noAccess"
        case .other: "other"
        }
    }
}
