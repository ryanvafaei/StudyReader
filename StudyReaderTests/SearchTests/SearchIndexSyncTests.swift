import Foundation
import GRDB
import Testing
@testable import StudyReader

/// The FTS index follows creates, updates and deletes (SPEC F-12 AC3, ADR-0013).
@Suite struct SearchIndexSyncTests {
    @Test func documentTitleChange() async throws {
        let env = try SearchTestEnvironment()
        let document = try await env.addDocument(title: "Old Zebra")

        let before = try await env.service.search("zebra")
        #expect(before.documents.map(\.documentId) == [document.id])

        try await env.documents.updateMetadata(
            id: document.id, title: "New Giraffe", author: "", categoryId: document.categoryId
        )

        let renamed = try await env.service.search("giraffe")
        #expect(renamed.documents.map(\.documentId) == [document.id])
        #expect(renamed.documents.first?.field == .titleOrAuthor)
        let old = try await env.service.search("zebra")
        #expect(old.isEmpty)
        try await env.checkIntegrity()
    }

    @Test func documentDelete() async throws {
        let env = try SearchTestEnvironment()
        let fileStore = TestFileStore.make()
        defer { TestFileStore.remove(fileStore) }
        let document = try await env.addDocument(title: "Organelles", pages: ["the mitochondria page"])
        try await env.addHighlight(documentId: document.id, text: "ribosome", note: "nucleolus")
        try await env.notes.saveDocumentNote(documentId: document.id, body: "lysosome", at: env.now())

        let words = ["organelles", "mitochondria", "ribosome", "nucleolus", "lysosome"]
        for word in words {
            let found = try await env.service.search(word)
            #expect(!found.isEmpty, "Before delete: \(word)")
        }

        let deleted = try await env.documents.delete(id: document.id, fileStore: fileStore)
        #expect(deleted)

        for word in words {
            let gone = try await env.service.search(word)
            #expect(gone.isEmpty, "After delete: \(word)")
        }
        try await env.checkIntegrity()
    }

    @Test func highlightCreateUpdateDelete() async throws {
        let env = try SearchTestEnvironment()
        let fileStore = TestFileStore.make()
        defer { TestFileStore.remove(fileStore) }
        let document = try await env.addDocument(title: "Biology")

        let highlight = try await env.addHighlight(documentId: document.id, text: "osmosis")
        let created = try await env.service.search("osmosis")
        #expect(created.highlights.map(\.highlightId) == [highlight.id])
        #expect(created.notes.isEmpty)

        let noteBefore = try await env.service.search("diffusion")
        #expect(noteBefore.isEmpty)
        try await env.highlights.updateNote(id: highlight.id, note: "diffusion across a membrane", at: env.now())
        let noted = try await env.service.search("diffusion")
        #expect(noted.notes.count == 1)
        #expect(noted.notes.first?.kind == .highlightNote)
        #expect(noted.notes.first?.highlightId == highlight.id)
        #expect(noted.highlights.isEmpty)

        let beforeColor = try await env.service.search("osmosis")
        try await env.highlights.updateColor(id: highlight.id, color: .blue, at: env.now())
        let afterColor = try await env.service.search("osmosis")
        #expect(afterColor == beforeColor)
        let noteAfterColor = try await env.service.search("diffusion")
        #expect(noteAfterColor == noted)

        let removed = try await env.highlights.delete(id: highlight.id, fileStore: fileStore)
        #expect(removed)
        let osmosis = try await env.service.search("osmosis")
        let diffusion = try await env.service.search("diffusion")
        #expect(osmosis.isEmpty)
        #expect(diffusion.isEmpty)
        try await env.checkIntegrity()
    }

    @Test func documentNoteUpsert() async throws {
        let env = try SearchTestEnvironment()
        let document = try await env.addDocument(title: "Notes")

        try await env.notes.saveDocumentNote(documentId: document.id, body: "first draft body", at: env.now())
        let first = try await env.service.search("draft")
        #expect(first.notes.map(\.documentId) == [document.id])

        try await env.notes.saveDocumentNote(documentId: document.id, body: "second revision body", at: env.now())
        let stale = try await env.service.search("draft")
        #expect(stale.isEmpty)
        let latest = try await env.service.search("revision")
        #expect(latest.notes.count == 1)
        #expect(latest.notes.first?.kind == .documentNote)
        let shared = try await env.service.search("body")
        #expect(shared.notes.count == 1)
        try await env.checkIntegrity()
    }

    @Test func reExtractionReplacesText() async throws {
        let env = try SearchTestEnvironment()
        let document = try await env.addDocument(title: "Reextracted", pages: ["alpha beta", "alpha again"])

        let before = try await env.service.search("alpha")
        #expect(before.documents.count == 2)

        try await env.setPages(["gamma delta"], documentId: document.id)

        let oldWord = try await env.service.search("alpha")
        let oldWord2 = try await env.service.search("beta")
        #expect(oldWord.isEmpty)
        #expect(oldWord2.isEmpty)
        let newWord = try await env.service.search("gamma")
        #expect(newWord.documents.count == 1)
        #expect(newWord.documents.first?.unitIndex == 0)
        try await env.checkIntegrity()
    }
}
