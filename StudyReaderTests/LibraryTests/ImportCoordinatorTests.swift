import Foundation
import Testing
@testable import StudyReader

/// Records the folder-access panel calls and answers with a fixed folder, so no real panel opens.
@MainActor
final class FolderPanelRecorder {
    struct Request: Equatable {
        let folder: URL
        let markdownFileName: String
    }

    private(set) var requests: [Request] = []
    private let answer: URL?

    init(answer: URL?) {
        self.answer = answer
    }

    func show(_ folder: URL, _ markdownFileName: String) async -> URL? {
        requests.append(Request(folder: folder, markdownFileName: markdownFileName))
        return answer
    }
}

/// Polls a condition on the main actor, at most 2,000 times 5 ms apart. Returns the final value.
@MainActor
private func pollUntil(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<2_000 {
        if condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// Records the VoiceOver announcements the coordinator makes, so no accessibility notification is posted in tests.
@MainActor
final class AnnouncementRecorder {
    private(set) var texts: [String] = []

    func record(_ text: String) {
        texts.append(text)
    }
}

@MainActor
@Suite("ImportCoordinator")
struct ImportCoordinatorTests {
    @Test
    func quietImportShowsNoAlertAndAnnounces() async throws {
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }
        let recorder = AnnouncementRecorder()
        let coordinator = ImportCoordinator(importService: harness.service, announce: recorder.record)
        let source = try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.plainMultiPage(), name: "lecture.pdf")

        coordinator.importURLs([source])
        #expect(coordinator.isImporting)

        let finished = await pollUntil { !coordinator.isImporting && coordinator.summaryHistory.count == 1 }
        #expect(finished)
        #expect(coordinator.summaryHistory == ["Imported 1"])
        #expect(coordinator.lastSummary == nil)
        #expect(recorder.texts == ["Imported 1"])
        #expect(try await harness.env.documentRepository.fetchAll().count == 1)
    }

    @Test
    func duplicateImportStillShowsTheSummary() async throws {
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }
        let recorder = AnnouncementRecorder()
        let coordinator = ImportCoordinator(importService: harness.service, announce: recorder.record)
        let source = try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.plainMultiPage(), name: "lecture.pdf")

        coordinator.importURLs([source])
        let firstFinished = await pollUntil { !coordinator.isImporting && coordinator.summaryHistory.count == 1 }
        #expect(firstFinished)

        coordinator.importURLs([source])
        let secondFinished = await pollUntil { !coordinator.isImporting && coordinator.summaryHistory.count == 2 }
        #expect(secondFinished)
        #expect(coordinator.lastSummary?.hasPrefix("Already in library:") == true)
        #expect(recorder.texts == ["Imported 1"])
        #expect(try await harness.env.documentRepository.fetchAll().count == 1)
    }

    @Test
    func reportNeedsAttentionOnlyForProblems() {
        let imported = ImportedDocument(documentId: "1", title: "A")
        var oneImported = ImportReport()
        oneImported.imported = [imported]
        #expect(oneImported.needsAttention == false)

        #expect(ImportReport().needsAttention == true)

        var duplicate = oneImported
        duplicate.duplicates = ["A"]
        #expect(duplicate.needsAttention == true)

        var unsupported = oneImported
        unsupported.unsupported = ["notes.docx"]
        #expect(unsupported.needsAttention == true)

        var failed = oneImported
        failed.failures = [ImportFailure(fileName: "broken.pdf", reason: .damaged)]
        #expect(failed.needsAttention == true)

        var unreadable = oneImported
        unreadable.unreadableImageCount = 1
        #expect(unreadable.needsAttention == true)

        var missing = oneImported
        missing.missingImageCount = 2
        #expect(missing.needsAttention == false)
    }

    @Test
    func passwordRoundTrip() async throws {
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }
        let coordinator = ImportCoordinator(importService: harness.service)
        let locked = try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.encrypted(password: "secret"), name: "locked.pdf")

        // Wrong password: the question is asked once and the batch ends with a failure summary.
        coordinator.importURLs([locked])
        let asked = await pollUntil { coordinator.passwordRequest != nil }
        #expect(asked)
        #expect(coordinator.passwordRequest?.fileName == "locked.pdf")
        coordinator.answerPassword("nope")
        let wrongFinished = await pollUntil { !coordinator.isImporting }
        #expect(wrongFinished)
        #expect(coordinator.passwordRequest == nil)
        #expect(coordinator.summaryHistory.last?.contains("locked.pdf") == true)
        #expect(try await harness.env.documentRepository.fetchAll().isEmpty)

        // Right password on a second batch: the file is imported.
        coordinator.importURLs([locked])
        let askedAgain = await pollUntil { coordinator.passwordRequest != nil }
        #expect(askedAgain)
        coordinator.answerPassword("secret")
        let rightFinished = await pollUntil { !coordinator.isImporting && coordinator.summaryHistory.count == 2 }
        #expect(rightFinished)
        #expect(coordinator.summaryHistory.last == "Imported 1")
        #expect(try await harness.env.documentRepository.fetchAll().count == 1)
    }

    @Test
    func largeFileDecline() async throws {
        // A threshold of 10 bytes makes every PDF "large".
        let harness = try ImportHarness.make(largeFileThreshold: 10)
        defer { harness.cleanup() }
        let coordinator = ImportCoordinator(importService: harness.service)
        let big = try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.plainMultiPage(), name: "big.pdf")

        coordinator.importURLs([big])
        let asked = await pollUntil { coordinator.largeFileRequest != nil }
        #expect(asked)
        #expect(coordinator.largeFileRequest?.fileName == "big.pdf")
        coordinator.answerLargeFile(false)
        #expect(coordinator.largeFileRequest == nil)

        let finished = await pollUntil { !coordinator.isImporting && !coordinator.summaryHistory.isEmpty }
        #expect(finished)
        #expect(coordinator.lastSummary?.contains("Skipped") == true)
        #expect(try await harness.env.documentRepository.fetchAll().isEmpty)
    }

    @Test
    func folderAccessUsesInjectedPanel() async throws {
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "ImportCoordinatorTests", directoryHint: .isDirectory)
            .appending(path: "images", directoryHint: .isDirectory)
        let granted = folder
        let recorder = FolderPanelRecorder(answer: granted)
        let coordinator = ImportCoordinator(importService: harness.service, folderPanel: recorder.show)

        let answer = await coordinator.requestFolderAccess(for: folder, markdownFileName: "notes.md")

        #expect(answer == granted)
        #expect(recorder.requests == [FolderPanelRecorder.Request(folder: folder, markdownFileName: "notes.md")])
    }

    @Test
    func batchesRunInOrder() async throws {
        let harness = try ImportHarness.make()
        defer { harness.cleanup() }
        let coordinator = ImportCoordinator(importService: harness.service)
        // Different page counts give different bytes, so the second file is not a duplicate of the first.
        let first = try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.plainMultiPage(pageCount: 5), name: "first.pdf")
        let second = try PDFFixtureBuilder.writeTemporary(PDFFixtureBuilder.plainMultiPage(pageCount: 3), name: "second.pdf")

        coordinator.importURLs([first])
        coordinator.importURLs([second])
        let finished = await pollUntil { !coordinator.isImporting && coordinator.summaryHistory.count == 2 }
        #expect(finished)
        #expect(coordinator.summaryHistory == ["Imported 1", "Imported 1"])

        let ids = await harness.queue.ids
        #expect(ids.count == 2)
        guard ids.count == 2 else { return }
        #expect(try await harness.document(id: ids[0]).originalFilename == "first.pdf")
        #expect(try await harness.document(id: ids[1]).originalFilename == "second.pdf")
    }
}
