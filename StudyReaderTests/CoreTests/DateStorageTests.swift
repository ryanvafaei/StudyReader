import Foundation
import GRDB
import Testing
@testable import StudyReader

@Suite struct DateStorageTests {
    /// 10,000 deterministic dates from 2026-01-01 to about 2029, spaced by a non-binary step.
    private static let samples: [Date] = (0..<10_000).map {
        Date(timeIntervalSinceReferenceDate: 788_918_400 + Double($0) * 9_467.123_456_7)
    }

    @Test func unroundedDatesCanDrift() {
        let drifting = Self.samples.filter { d in
            Date(timeIntervalSince1970: d.timeIntervalSince1970) != d
        }
        #expect(drifting.count > 0)
    }

    @Test func storageRoundedDatesSurviveUnixSeconds() {
        let failures = Self.samples.filter { d in
            let r = d.storageRounded
            return Date(timeIntervalSince1970: r.timeIntervalSince1970) != r
        }
        #expect(failures.count == 0)
    }

    @Test func storageRoundedIsOnGridAndClose() {
        for d in Self.samples {
            let r = d.storageRounded
            #expect(r.timeIntervalSinceReferenceDate * 1024 == (r.timeIntervalSinceReferenceDate * 1024).rounded())
            #expect(r <= d)
            #expect(d.timeIntervalSince(r) < 1.0 / 1024)
            #expect(r.storageRounded == r)
        }
    }

    @Test func recordRoundTripIsExact() async throws {
        let db = try AppDatabase.makeInMemory()
        let documentId = "10000000-0000-0000-0000-0000000000b1"
        let document = TestData.document(id: documentId)
        let highlight = TestData.highlight(
            documentId: documentId,
            id: "20000000-0000-0000-0000-0000000000b1",
            createdAt: Date(timeIntervalSinceReferenceDate: 815_000_000.123).storageRounded
        )

        try await db.writer.write { db in
            try document.insert(db)
            try highlight.insert(db)
            try FTSIntegrity.check(db)
        }
        let fetched = try await db.reader.read { db in
            try Highlight.fetchOne(db, key: highlight.id)
        }
        #expect(fetched == highlight)
    }

    @Test func systemNowIsStorageRounded() {
        let date = SystemNow()()
        #expect(date == date.storageRounded)
    }

    private static let pastCardId = "30000000-0000-0000-0000-0000000000c1"
    private static let futureCardId = "30000000-0000-0000-0000-0000000000c2"

    /// Inserts a document, a highlight and two cards due one day before and one day after `TestData.referenceDate`.
    private static func insertPastAndFutureCards(_ db: Database) throws {
        let documentId = "10000000-0000-0000-0000-0000000000c1"
        let highlightId = "20000000-0000-0000-0000-0000000000c1"
        try TestData.document(id: documentId).insert(db)
        try TestData.highlight(documentId: documentId, id: highlightId).insert(db)
        try TestData.reviewCard(highlightId: highlightId, id: pastCardId,
                                dueAt: TestData.referenceDate.addingTimeInterval(-86_400)).insert(db)
        try TestData.reviewCard(highlightId: highlightId, id: futureCardId,
                                dueAt: TestData.referenceDate.addingTimeInterval(86_400)).insert(db)
    }

    @Test func dateQueryArgumentsCompareAsUnixSeconds() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        try await appDatabase.writer.write { db in
            try Self.insertPastAndFutureCards(db)
            let now = TestData.referenceDate.databaseUnixSeconds
            let past = try ReviewCard.filter(Column("dueAt") <= now).fetchAll(db).map(\.id)
            #expect(past == [Self.pastCardId])
            let future = try ReviewCard.filter(Column("dueAt") > now).fetchAll(db).map(\.id)
            #expect(future == [Self.futureCardId])
            let raw = try String.fetchAll(db, sql: "SELECT id FROM reviewCard WHERE dueAt <= ?", arguments: [now])
            #expect(raw == [Self.pastCardId])
            try FTSIntegrity.check(db)
        }
    }

    // Documents GRDB behaviour that ADR-0012 works around. If this starts failing, GRDB changed how it binds Date: report it, don't delete or "fix" this test.
    @Test func rawDateArgumentsBindAsText() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        try await appDatabase.writer.write { db in
            let boundDate = try String.fetchOne(db, sql: "SELECT typeof(?)", arguments: [TestData.referenceDate])
            #expect(boundDate == "text")
            let boundSeconds = try String.fetchOne(
                db, sql: "SELECT typeof(?)", arguments: [TestData.referenceDate.databaseUnixSeconds])
            #expect(boundSeconds == "real")
            try Self.insertPastAndFutureCards(db)
            let wrongLessThan = try ReviewCard.filter(Column("dueAt") <= TestData.referenceDate).fetchCount(db)
            #expect(wrongLessThan == 2)
            let wrongGreaterThan = try ReviewCard.filter(Column("dueAt") > TestData.referenceDate).fetchCount(db)
            #expect(wrongGreaterThan == 0)
            try FTSIntegrity.check(db)
        }
    }

    @Test func databaseUnixSecondsMatchesStoredValue() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let documentId = "10000000-0000-0000-0000-0000000000c3"
        let highlightId = "20000000-0000-0000-0000-0000000000c3"
        let cardId = "30000000-0000-0000-0000-0000000000c3"
        let date = Date(timeIntervalSinceReferenceDate: 815_000_000.123).storageRounded
        try await appDatabase.writer.write { db in
            try TestData.document(id: documentId).insert(db)
            try TestData.highlight(documentId: documentId, id: highlightId).insert(db)
            try TestData.reviewCard(highlightId: highlightId, id: cardId, dueAt: date).insert(db)

            #expect(date.databaseUnixSeconds == date.timeIntervalSince1970)
            let stored = try Double.fetchOne(db, sql: "SELECT dueAt FROM reviewCard WHERE id = ?", arguments: [cardId])
            #expect(stored == date.databaseUnixSeconds)
            let matches = try ReviewCard.filter(Column("dueAt") == date.databaseUnixSeconds).fetchCount(db)
            #expect(matches == 1)
            try FTSIntegrity.check(db)
        }
    }

    @Test func dateColumnAssignmentsStoreReal() async throws {
        let appDatabase = try AppDatabase.makeInMemory()
        let newDue = Date(timeIntervalSinceReferenceDate: 815_000_000.5).storageRounded
        try await appDatabase.writer.write { db in
            try Self.insertPastAndFutureCards(db)
            _ = try ReviewCard.filter(key: Self.pastCardId)
                .updateAll(db, Column("dueAt").set(to: newDue.databaseUnixSeconds))
            let type = try String.fetchOne(
                db, sql: "SELECT typeof(dueAt) FROM reviewCard WHERE id = ?", arguments: [Self.pastCardId])
            #expect(type == "real")
            let decoded = try ReviewCard.fetchOne(db, key: Self.pastCardId)?.dueAt
            #expect(decoded == newDue)
            try FTSIntegrity.check(db)
        }
    }
}
