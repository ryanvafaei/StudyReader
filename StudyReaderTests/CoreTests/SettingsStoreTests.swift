import Foundation
import Testing
@testable import StudyReader

@Suite struct SettingsStoreTests {
    @Test func defaults() {
        let store = TestSettings.make()
        defer { TestSettings.remove(store) }

        #expect(store.defaultCategoryId == BuiltinCategory.lectureSlides.id)
        #expect(store.autoHighlight == true)
        #expect(store.currentColor == .yellow)
        #expect(store.invertPDFInDarkMode == true)
        #expect(store.legacyGoogleExportFolderId == nil)
        #expect(store.libraryLayout == .grid)
        #expect(store.librarySort == .dateAdded)
    }

    @Test func roundTrips() throws {
        let store = TestSettings.make()
        defer { TestSettings.remove(store) }
        let suiteName = try #require(store.suiteName)

        store.defaultCategoryId = BuiltinCategory.paper.id
        store.autoHighlight = false
        store.currentColor = .purple
        store.invertPDFInDarkMode = false
        store.legacyGoogleExportFolderId = "folder-123"
        store.libraryLayout = .list
        store.librarySort = .title
        store.setColorLabel("Review", for: .blue)

        let reread = SettingsStore(suiteName: suiteName)
        #expect(reread.defaultCategoryId == BuiltinCategory.paper.id)
        #expect(reread.autoHighlight == false)
        #expect(reread.currentColor == .purple)
        #expect(reread.invertPDFInDarkMode == false)
        #expect(reread.legacyGoogleExportFolderId == "folder-123")
        #expect(reread.libraryLayout == .list)
        #expect(reread.librarySort == .title)
        #expect(reread.colorLabel(for: .blue) == "Review")

        store.legacyGoogleExportFolderId = nil
        #expect(SettingsStore(suiteName: suiteName).legacyGoogleExportFolderId == nil)
        #expect(store.defaults.object(forKey: "settings.googleExportFolderId") == nil)
    }

    @Test func googleAppFolderIdPerAccount() throws {
        let store = TestSettings.make()
        defer { TestSettings.remove(store) }
        let key = "settings.googleAppFolderIds"

        store.setGoogleAppFolderId("FOLDER_A", forAccount: "A@x.com")
        #expect(store.googleAppFolderId(forAccount: " a@X.com ") == "FOLDER_A")
        #expect(store.googleAppFolderId(forAccount: "b@x.com") == nil)

        store.setGoogleAppFolderId("FOLDER_B", forAccount: "b@x.com")
        #expect(store.googleAppFolderId(forAccount: "a@x.com") == "FOLDER_A")
        #expect(store.googleAppFolderId(forAccount: "b@x.com") == "FOLDER_B")
        let stored = try #require(store.defaults.dictionary(forKey: key))
        #expect(stored.count == 2)
        #expect(stored.keys.allSatisfy { !$0.contains("@") })

        store.setGoogleAppFolderId(nil, forAccount: "A@x.com")
        #expect(store.googleAppFolderId(forAccount: "a@x.com") == nil)
        #expect(store.googleAppFolderId(forAccount: "b@x.com") == "FOLDER_B")

        store.setGoogleAppFolderId("IGNORED", forAccount: "  ")
        store.setGoogleAppFolderId("IGNORED", forAccount: "")
        #expect(store.googleAppFolderId(forAccount: "") == nil)
        #expect(store.googleAppFolderId(forAccount: "  ") == nil)
        #expect(store.defaults.dictionary(forKey: key)?.count == 1)

        store.setGoogleAppFolderId(nil, forAccount: "b@x.com")
        #expect(store.defaults.object(forKey: key) == nil)
    }

    @Test func colorLabels() {
        let store = TestSettings.make()
        defer { TestSettings.remove(store) }

        #expect(store.colorLabel(for: .yellow) == "Key concept")
        #expect(store.colorLabel(for: .green) == "Exam")
        #expect(store.colorLabel(for: .blue) == "Connection")
        #expect(store.colorLabel(for: .pink) == "Question")
        #expect(store.colorLabel(for: .purple) == "Don't understand")

        store.setColorLabel("  Exam prep ", for: .green)
        #expect(store.colorLabel(for: .green) == "Exam prep")

        store.setColorLabel("", for: .green)
        #expect(store.colorLabel(for: .green) == "Exam")
    }

    @Test func environmentUsesEphemeralSuiteInMemory() throws {
        let environment = try AppEnvironment.inMemory()
        defer { TestFileStore.remove(environment.fileStore) }

        #expect(environment.settingsStore.suiteName == SettingsStore.ephemeralSuiteName)
    }
}
