import Testing
@testable import StudyReader

@Suite("RootModel")
@MainActor
struct RootModelTests {
    @Test func defaultsToLibrary() throws {
        let environment = try AppEnvironment.inMemory()
        defer { TestFileStore.remove(environment.fileStore) }
        let model = RootModel(environment: environment)

        #expect(model.selection == .library)
    }
}
