import Testing
@testable import StudyReader

@Suite("DriveFolderLink")
struct DriveFolderLinkTests {
    private static let id = "1AbCdEfGhIjKlMnOpQrStUvWxYz_-0123"

    @Test(.timeLimit(.minutes(1)))
    func acceptedForms() {
        let id = Self.id
        let accepted = [
            "https://drive.google.com/drive/folders/\(id)",
            "https://drive.google.com/drive/folders/\(id)?usp=sharing",
            "https://drive.google.com/drive/folders/\(id)?usp=drive_link&resourcekey=abc",
            "https://drive.google.com/drive/u/0/folders/\(id)",
            "https://drive.google.com/drive/u/12/folders/\(id)?usp=sharing",
            "https://drive.google.com/open?id=\(id)",
            "https://drive.google.com/open?usp=sharing&id=\(id)",
            id,
            "  \(id)\n",
            "  https://drive.google.com/drive/folders/\(id)  ",
        ]
        for input in accepted {
            #expect(DriveFolderLink.folderId(from: input) == id, "input: \(input)")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectedForms() {
        let rejected = [
            "https://example.com/folders/x",
            "https://example.com/drive/folders/\(Self.id)",
            "http://drive.google.com/drive/folders/\(Self.id)",
            "https://drive.google.com/drive/folders/short",
            "https://drive.google.com/file/d/\(Self.id)/view",
            "https://drive.google.com/open?id=short",
            "https://drive.google.com/drive/u/x/folders/\(Self.id)",
            "short",
            "has space in it 1234567890",
            "",
            "   ",
        ]
        for input in rejected {
            #expect(DriveFolderLink.folderId(from: input) == nil, "input: \(input)")
        }
    }
}
