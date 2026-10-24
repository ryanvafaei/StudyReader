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
}
