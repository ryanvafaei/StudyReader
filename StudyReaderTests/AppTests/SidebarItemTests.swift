import Testing
@testable import StudyReader

@Suite struct SidebarItemTests {
    @Test func allCasesInSpecOrder() {
        #expect(SidebarItem.allCases.map(\.rawValue)
            == ["library", "highlights", "review", "themedReviews", "tags", "categories"])
        #expect(SidebarItem.allCases.map(\.title)
            == ["Library", "Highlights", "Review", "Themed Reviews", "Tags", "Categories"])
    }
}
