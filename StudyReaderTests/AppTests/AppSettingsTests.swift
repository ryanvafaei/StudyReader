import Foundation
import Testing
@testable import StudyReader

@Suite("AppSettings") @MainActor
struct AppSettingsTests {
    @Test func readsStoreValues() {
        let store = TestSettings.make()
        defer { TestSettings.remove(store) }
        store.defaultCategoryId = BuiltinCategory.paper.id
        store.autoHighlight = false
        store.currentColor = .blue
        store.invertPDFInDarkMode = false
        store.googleExportFolderId = "folder-123"
        store.setColorLabel("Exam prep", for: .green)

        let settings = AppSettings(store: store)

        #expect(settings.defaultCategoryId == BuiltinCategory.paper.id)
        #expect(settings.autoHighlight == false)
        #expect(settings.currentColor == .blue)
        #expect(settings.invertPDFInDarkMode == false)
        #expect(settings.googleExportFolderId == "folder-123")
        #expect(settings.label(for: .green) == "Exam prep")
        #expect(settings.colorLabels.count == 5)
        #expect(settings.colorLabels[1] == "Exam prep")
        #expect(settings.label(for: .yellow) == SettingsStore.defaultColorLabel(for: .yellow))
    }

    @Test func writesThrough() {
        let store = TestSettings.make()
        defer { TestSettings.remove(store) }
        let settings = AppSettings(store: store)

        settings.defaultCategoryId = BuiltinCategory.paper.id
        settings.autoHighlight = false
        settings.currentColor = .pink
        settings.invertPDFInDarkMode = false
        settings.googleExportFolderId = "folder-456"

        // A fresh store over the same suite sees every new value.
        let reread = SettingsStore(suiteName: store.suiteName)
        #expect(reread.defaultCategoryId == BuiltinCategory.paper.id)
        #expect(reread.autoHighlight == false)
        #expect(reread.currentColor == .pink)
        #expect(reread.invertPDFInDarkMode == false)
        #expect(reread.googleExportFolderId == "folder-456")

        settings.googleExportFolderId = nil
        #expect(SettingsStore(suiteName: store.suiteName).googleExportFolderId == nil)

        settings.setLabel("Exam prep", for: .green)
        #expect(settings.label(for: .green) == "Exam prep")
        #expect(settings.colorLabels[1] == "Exam prep")
        #expect(SettingsStore(suiteName: store.suiteName).colorLabel(for: .green) == "Exam prep")

        settings.setLabel("", for: .green)
        #expect(settings.label(for: .green) == "Exam")
        #expect(settings.colorLabels[1] == "Exam")
        #expect(SettingsStore(suiteName: store.suiteName).colorLabel(for: .green) == "Exam")
    }

    @Test func sessionCreatedOnReady() async throws {
        let model = AppLaunchModel { try AppEnvironment.inMemory() }
        #expect(model.session == nil)

        await model.start()

        guard case .ready(let environment) = model.state else {
            Issue.record("Expected .ready after start()")
            return
        }
        #expect(model.session != nil)
        #expect(model.session?.environment.fileStore == environment.fileStore)
        TestFileStore.remove(environment.fileStore)
    }
}
