import Foundation
import Testing
@testable import StudyReader

@Suite("DriveErrorReason")
struct DriveErrorReasonTests {
    private static func body(_ reasons: String...) -> Data {
        let items = reasons.map { #"{"domain":"usageLimits","reason":"\#($0)"}"# }.joined(separator: ",")
        return Data(#"{"error":{"errors":[\#(items)],"code":403}}"#.utf8)
    }

    @Test func parsesReasons() {
        #expect(DriveErrorReason.parse(Self.body("userRateLimitExceeded")) == .rateLimited)
        #expect(DriveErrorReason.parse(Self.body("rateLimitExceeded")) == .rateLimited)
        #expect(DriveErrorReason.parse(Self.body("dailyLimitExceeded")) == .dailyLimit)
        #expect(DriveErrorReason.parse(Self.body("storageQuotaExceeded")) == .storageFull)
        #expect(DriveErrorReason.parse(Self.body("appNotAuthorizedToFile")) == .noAccess)
        #expect(DriveErrorReason.parse(Self.body("insufficientFilePermissions")) == .noAccess)
        #expect(DriveErrorReason.parse(Data(#"{"error":{"errors":[{"reason":"somethingNew"}]}}"#.utf8)) == .other)
        #expect(DriveErrorReason.parse(Data("{}".utf8)) == .other)
        #expect(DriveErrorReason.parse(Data()) == .other)
        #expect(DriveErrorReason.parse(Data("not json".utf8)) == .other)
        #expect(DriveErrorReason.parse(Self.body("somethingNew", "storageQuotaExceeded")) == .storageFull)
    }

    @Test func oddShapesAreOther() {
        #expect(DriveErrorReason.parse(Data(#"{"error":"storageQuotaExceeded"}"#.utf8)) == .other)
        #expect(DriveErrorReason.parse(Data(#"{"error":{"errors":[]}}"#.utf8)) == .other)
        #expect(DriveErrorReason.parse(Data(#"{"error":{"errors":[{"message":"x"}]}}"#.utf8)) == .other)
    }

    @Test func logNamesAreFixedNames() {
        #expect(DriveErrorReason.rateLimited.logName == "rateLimitExceeded")
        #expect(DriveErrorReason.dailyLimit.logName == "dailyLimitExceeded")
        #expect(DriveErrorReason.storageFull.logName == "storageQuotaExceeded")
        #expect(DriveErrorReason.noAccess.logName == "noAccess")
        #expect(DriveErrorReason.other.logName == "other")
    }
}
