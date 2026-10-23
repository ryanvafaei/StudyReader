import Foundation
import Testing
@testable import StudyReader

/// Proves the app bundle reads its version from build settings (T11).
@Suite struct BundleVersionTests {
    @Test func versionComesFromBuildSettings() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let shortVersion = try #require(info["CFBundleShortVersionString"] as? String)
        let buildVersion = try #require(info["CFBundleVersion"] as? String)

        #expect(shortVersion == "0.1.0")
        #expect(!buildVersion.isEmpty)
        #expect(buildVersion != "$(CURRENT_PROJECT_VERSION)")
    }
}
