import Foundation
import Testing
@testable import StudyReader

@Suite struct LinkPolicyTests {
    @Test func onlyWebAndMailLinksOpen() throws {
        let allowed = [
            "https://example.com", "http://example.com", "HTTPS://EXAMPLE.COM", "mailto:a@example.com",
        ]
        for string in allowed {
            #expect(LinkPolicy.isOpenable(try #require(URL(string: string))), "\(string)")
        }
        let blocked = [
            "file:///System/Applications/Calculator.app", "javascript:alert(1)", "smb://example.invalid/share",
            "studyreader-custom://x", "x-apple.systempreferences:", "ftp://example.com", "relative/path",
        ]
        for string in blocked {
            #expect(!LinkPolicy.isOpenable(try #require(URL(string: string))), "\(string)")
        }
    }

    @Test func schemesMatchTheReader() {
        #expect(LinkPolicy.openableSchemes == ["http", "https", "mailto"])
    }
}
