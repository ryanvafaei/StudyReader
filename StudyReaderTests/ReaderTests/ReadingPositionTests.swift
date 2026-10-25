import Foundation
import Testing
@testable import StudyReader

@MainActor
@Suite("ReadingPosition")
struct ReadingPositionTests {
    private static let documentId = "30000000-0000-0000-0000-0000000000C1"

    @Test(.timeLimit(.minutes(1)))
    func restoresPosition() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        try await ReaderTestSupport.insertDocument(session, id: Self.documentId, withFile: true)

        let first = ReaderModel(documentId: Self.documentId, session: session)
        await first.load()
        first.pdfPositionChanged(PDFPosition(pageIndex: 3, offsetY: 412.5), pageCount: 10)
        await first.flushPosition()

        let second = ReaderModel(documentId: Self.documentId, session: session)
        await second.load()
        #expect(second.initialPDFPosition == PDFPosition(pageIndex: 3, offsetY: 412.5))

        let row = await ReaderTestSupport.row(session, id: Self.documentId)
        #expect(abs((row?.progress ?? -1) - 0.4) < 0.0001)
    }

    @Test(.timeLimit(.minutes(1)))
    func restoresTextOffset() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        try await ReaderTestSupport.insertDocument(session, id: Self.documentId, withFile: true)

        let first = ReaderModel(documentId: Self.documentId, session: session)
        await first.load()
        first.textPositionChanged(offset: 250, textLength: 1000)
        await first.flushPosition()

        let second = ReaderModel(documentId: Self.documentId, session: session)
        await second.load()
        #expect(second.initialTextOffset == 250)

        let row = await ReaderTestSupport.row(session, id: Self.documentId)
        #expect(abs((row?.progress ?? -1) - 0.25) < 0.0001)
    }

    @Test(.timeLimit(.minutes(1)))
    func marksLastOpened() async throws {
        let session = try ReaderTestSupport.makeSession()
        defer { ReaderTestSupport.cleanUp(session) }
        try await ReaderTestSupport.insertDocument(session, id: Self.documentId, withFile: true)

        let model = ReaderModel(documentId: Self.documentId, session: session)
        await model.load()

        let row = await ReaderTestSupport.row(session, id: Self.documentId)
        #expect(row?.lastOpenedAt == TestData.referenceDate)
    }

    @Test(.timeLimit(.minutes(1)))
    func onlyLatestPositionIsSaved() async throws {
        let sleeper = ManualSleeper()
        let session = try ReaderTestSupport.makeSession(sleeper: sleeper)
        defer { ReaderTestSupport.cleanUp(session) }
        try await ReaderTestSupport.insertDocument(session, id: Self.documentId, withFile: true)

        let model = ReaderModel(documentId: Self.documentId, session: session)
        await model.load()
        model.pdfPositionChanged(PDFPosition(pageIndex: 1, offsetY: 10), pageCount: 10)
        model.pdfPositionChanged(PDFPosition(pageIndex: 2, offsetY: 20), pageCount: 10)
        let latest = PDFPosition(pageIndex: 5, offsetY: 99)
        model.pdfPositionChanged(latest, pageCount: 10)

        await sleeper.waitForSleepers(3)
        await sleeper.resumeAll()

        let saved = await ReaderTestSupport.waitUntil {
            let row = await ReaderTestSupport.row(session, id: Self.documentId)
            return row?.pdfPosition == latest
        }
        #expect(saved)
    }
}
