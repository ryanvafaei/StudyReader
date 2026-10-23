import Testing
@testable import StudyReader

@Suite("RootModel")
@MainActor
struct RootModelTests {
    @Test func defaultsToLibrary() throws {
        let model = RootModel(environment: try AppEnvironment.inMemory())

        #expect(model.selection == .library)
    }
}
