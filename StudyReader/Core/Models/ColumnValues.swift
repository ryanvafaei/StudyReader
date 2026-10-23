import Foundation

/// document.pdfPosition
struct PDFPosition: Codable, Sendable, Equatable {
    var pageIndex: Int
    var offsetY: Double
}

/// documentText.runs element; offsets relative to that row's text (ARCHITECTURE §6 step 9)
struct TextRun: Codable, Sendable, Equatable {
    var start: Int
    var length: Int
    var bold: Bool
    var italic: Bool
    var mono: Bool
    var link: String?
}

enum TagMatchMode: String, Codable, Sendable, CaseIterable {
    case any, all
}

/// themedReview.filter
struct ThemedReviewFilter: Codable, Sendable, Equatable {
    var tagIds: [String] = []
    var tagMode: TagMatchMode = .any
    var documentIds: [String] = []
    var categoryIds: [String] = []
    var colors: [HighlightColor] = []      // encodes as ints

    init(tagIds: [String] = [], tagMode: TagMatchMode = .any, documentIds: [String] = [],
         categoryIds: [String] = [], colors: [HighlightColor] = []) {
        self.tagIds = tagIds
        self.tagMode = tagMode
        self.documentIds = documentIds
        self.categoryIds = categoryIds
        self.colors = colors
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagIds = try container.decodeIfPresent([String].self, forKey: .tagIds) ?? []
        tagMode = try container.decodeIfPresent(TagMatchMode.self, forKey: .tagMode) ?? .any
        documentIds = try container.decodeIfPresent([String].self, forKey: .documentIds) ?? []
        categoryIds = try container.decodeIfPresent([String].self, forKey: .categoryIds) ?? []
        colors = try container.decodeIfPresent([HighlightColor].self, forKey: .colors) ?? []
    }
}

/// themedReview.interval
struct ReviewInterval: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable, CaseIterable { case daily, everyNDays, weekdays }
    var kind: Kind
    var n: Int?               // kind == .everyNDays only
    var weekdays: [Int]?      // kind == .weekdays only; Calendar weekday numbers 1 = Sunday … 7 = Saturday

    static let daily = ReviewInterval(kind: .daily, n: nil, weekdays: nil)

    static func everyNDays(_ n: Int) -> ReviewInterval {
        ReviewInterval(kind: .everyNDays, n: n, weekdays: nil)
    }

    static func weekdays(_ days: [Int]) -> ReviewInterval {
        ReviewInterval(kind: .weekdays, n: nil, weekdays: days)
    }
}

/// exportTarget.scope
struct ExportScope: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable, CaseIterable { case document, tag, category, themedReview, all }
    var kind: Kind
    var id: String?           // nil only for .all

    static let all = ExportScope(kind: .all, id: nil)

    static func document(_ id: String) -> ExportScope {
        ExportScope(kind: .document, id: id)
    }

    static func tag(_ id: String) -> ExportScope {
        ExportScope(kind: .tag, id: id)
    }

    static func category(_ id: String) -> ExportScope {
        ExportScope(kind: .category, id: id)
    }

    static func themedReview(_ id: String) -> ExportScope {
        ExportScope(kind: .themedReview, id: id)
    }
}

enum ExportGroupBy: String, Codable, Sendable, CaseIterable {
    case document, tag
}

/// exportTarget.options (SPEC F-21 defaults)
struct ExportOptions: Codable, Sendable, Equatable {
    var includeNotes: Bool = true
    var includeDocumentNotes: Bool = true
    var includeImages: Bool = true
    var groupBy: ExportGroupBy = .document

    init(includeNotes: Bool = true, includeDocumentNotes: Bool = true,
         includeImages: Bool = true, groupBy: ExportGroupBy = .document) {
        self.includeNotes = includeNotes
        self.includeDocumentNotes = includeDocumentNotes
        self.includeImages = includeImages
        self.groupBy = groupBy
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        includeNotes = try container.decodeIfPresent(Bool.self, forKey: .includeNotes) ?? true
        includeDocumentNotes = try container.decodeIfPresent(Bool.self, forKey: .includeDocumentNotes) ?? true
        includeImages = try container.decodeIfPresent(Bool.self, forKey: .includeImages) ?? true
        groupBy = try container.decodeIfPresent(ExportGroupBy.self, forKey: .groupBy) ?? .document
    }
}
