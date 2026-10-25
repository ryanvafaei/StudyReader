import Foundation
import Testing
@testable import StudyReader

@MainActor
@Suite("ReaderRouter")
struct ReaderRouterTests {
    private static let documentId = "30000000-0000-0000-0000-0000000000D1"

    @Test
    func pendingLocationIsTakenOnce() {
        let router = ReaderRouter()
        router.setPendingLocation(.page(1), for: Self.documentId)

        #expect(router.takePendingLocation(for: Self.documentId) == .page(1))
        #expect(router.takePendingLocation(for: Self.documentId) == nil)
        #expect(router.pendingLocations[Self.documentId] == nil)
    }

    @Test
    func settingNilRemovesPendingLocation() {
        let router = ReaderRouter()
        router.setPendingLocation(.documentNote, for: Self.documentId)
        router.setPendingLocation(nil, for: Self.documentId)

        #expect(router.takePendingLocation(for: Self.documentId) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func loadTakesPendingLocation() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        try await ReaderTestSupport.insertDocument(session, id: Self.documentId, withFile: true)

        session.router.setPendingLocation(.page(2), for: Self.documentId)
        let model = ReaderModel(documentId: Self.documentId, session: session)
        await model.load()

        #expect(model.pendingLocation == .page(2))
        #expect(session.router.pendingLocations[Self.documentId] == nil)
    }
}
