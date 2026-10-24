import Testing
@testable import StudyReader

@Suite struct MetadataDefaultsTests {
    @Test func usesMetadataTitle() {
        #expect(MetadataDefaults.title(metadataTitle: "Neural Networks", fileName: "lec3.pdf") == "Neural Networks")
        #expect(MetadataDefaults.title(metadataTitle: "  Gradient Descent\n", fileName: "x.pdf") == "Gradient Descent")
    }

    @Test func fallsBackToFileName() {
        let rejected: [String?] = [
            nil, "", "slides.pptx", "C:\\docs\\a", "1234", "Untitled", "PowerPoint Presentation",
            "Microsoft Word - notes.docx",
        ]
        for metadataTitle in rejected {
            #expect(MetadataDefaults.title(metadataTitle: metadataTitle, fileName: "Lecture 3.PDF") == "Lecture 3")
        }
        #expect(MetadataDefaults.title(metadataTitle: nil, fileName: "README") == "README")
        #expect(MetadataDefaults.title(metadataTitle: nil, fileName: ".pdf") == ".pdf")
    }

    @Test func author() {
        #expect(MetadataDefaults.author(metadataAuthor: "  Ada ") == "Ada")
        #expect(MetadataDefaults.author(metadataAuthor: nil) == "")
    }
}
