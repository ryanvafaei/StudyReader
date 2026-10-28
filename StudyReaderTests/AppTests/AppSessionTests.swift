import Testing
@testable import StudyReader

@Suite("AppSession")
@MainActor
struct AppSessionTests {
    @Test func librarySelectionStartsEmptyAndKeepsItsValue() throws {
        let environment = try AppEnvironment.inMemory()
        defer { TestFileStore.remove(environment.fileStore) }
        let session = AppSession(environment: environment)

        #expect(session.librarySelection == nil)
        session.librarySelection = "d1"
        #expect(session.librarySelection == "d1")
        session.librarySelection = nil
        #expect(session.librarySelection == nil)
    }
}
