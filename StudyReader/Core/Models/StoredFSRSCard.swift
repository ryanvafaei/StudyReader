import Foundation

/// Our JSON for `reviewCard.fsrsCard` (ADR-0021). Dates encode as Unix seconds, keys sorted.
/// The stored shape never depends on the swift-fsrs encoding; `ReviewScheduler` maps to and from the library.
struct StoredFSRSCard: Codable, Sendable, Equatable {
    var due: Date
    var stability: Double = 0
    var difficulty: Double = 0
    var elapsedDays: Double = 0
    var scheduledDays: Double = 0
    var learningSteps: Int = 0
    var reps: Int = 0
    var lapses: Int = 0
    var state: ReviewCardState = .new
    var lastReview: Date? = nil

    /// A card never reviewed: state new, all counters 0, lastReview nil, due = due.storageRounded.
    static func new(due: Date) -> StoredFSRSCard {
        StoredFSRSCard(due: due.storageRounded)
    }

    /// JSONEncoder, outputFormatting [.sortedKeys], dateEncodingStrategy .secondsSince1970; nil lastReview is omitted.
    func json() throws -> String {
        String(decoding: try JSONEncoder.storedFSRS.encode(self), as: UTF8.self)
    }

    enum CodingKeys: String, CodingKey {
        case due, stability, difficulty, elapsedDays, scheduledDays, learningSteps, reps, lapses, state, lastReview
    }
}

// Initializers live in extensions so the compiler keeps the memberwise initializer.
extension StoredFSRSCard {
    /// Every key is optional: missing → the defaults above; missing `due` → Date(timeIntervalSince1970: 0). "{}" decodes.
    init(json: String) throws {
        self = try JSONDecoder.storedFSRS.decode(StoredFSRSCard.self, from: Data(json.utf8))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        due = try c.decodeIfPresent(Date.self, forKey: .due) ?? Date(timeIntervalSince1970: 0)
        stability = try c.decodeIfPresent(Double.self, forKey: .stability) ?? 0
        difficulty = try c.decodeIfPresent(Double.self, forKey: .difficulty) ?? 0
        elapsedDays = try c.decodeIfPresent(Double.self, forKey: .elapsedDays) ?? 0
        scheduledDays = try c.decodeIfPresent(Double.self, forKey: .scheduledDays) ?? 0
        learningSteps = try c.decodeIfPresent(Int.self, forKey: .learningSteps) ?? 0
        reps = try c.decodeIfPresent(Int.self, forKey: .reps) ?? 0
        lapses = try c.decodeIfPresent(Int.self, forKey: .lapses) ?? 0
        state = try c.decodeIfPresent(ReviewCardState.self, forKey: .state) ?? .new
        lastReview = try c.decodeIfPresent(Date.self, forKey: .lastReview)
    }
}

/// Our JSON for `reviewLog.fsrsLog`. Fields describe the card BEFORE the review, plus the review time.
struct StoredFSRSLog: Codable, Sendable, Equatable {
    var rating: ReviewRating
    var state: ReviewCardState
    var due: Date
    var stability: Double
    var difficulty: Double
    var elapsedDays: Double
    var lastElapsedDays: Double
    var scheduledDays: Double
    var learningSteps: Int
    var review: Date

    func json() throws -> String {
        String(decoding: try JSONEncoder.storedFSRS.encode(self), as: UTF8.self)
    }

    enum CodingKeys: String, CodingKey {
        case rating, state, due, stability, difficulty, elapsedDays, lastElapsedDays, scheduledDays, learningSteps, review
    }
}

extension StoredFSRSLog {
    /// Same coding rules as `StoredFSRSCard` (missing keys → 0 / .new / .again / 1970).
    init(json: String) throws {
        self = try JSONDecoder.storedFSRS.decode(StoredFSRSLog.self, from: Data(json.utf8))
    }

    init(from decoder: Decoder) throws {
        let epoch = Date(timeIntervalSince1970: 0)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rating = try c.decodeIfPresent(ReviewRating.self, forKey: .rating) ?? .again
        state = try c.decodeIfPresent(ReviewCardState.self, forKey: .state) ?? .new
        due = try c.decodeIfPresent(Date.self, forKey: .due) ?? epoch
        stability = try c.decodeIfPresent(Double.self, forKey: .stability) ?? 0
        difficulty = try c.decodeIfPresent(Double.self, forKey: .difficulty) ?? 0
        elapsedDays = try c.decodeIfPresent(Double.self, forKey: .elapsedDays) ?? 0
        lastElapsedDays = try c.decodeIfPresent(Double.self, forKey: .lastElapsedDays) ?? 0
        scheduledDays = try c.decodeIfPresent(Double.self, forKey: .scheduledDays) ?? 0
        learningSteps = try c.decodeIfPresent(Int.self, forKey: .learningSteps) ?? 0
        review = try c.decodeIfPresent(Date.self, forKey: .review) ?? epoch
    }
}

/// `reviewLog.rating` raw values = FSRS `Rating` raw values (ADR-0021). Never `.manual`.
enum ReviewRating: Int, Codable, Sendable, CaseIterable {
    case again = 1, hard = 2, good = 3, easy = 4
}

private extension JSONEncoder {
    static var storedFSRS: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}

private extension JSONDecoder {
    static var storedFSRS: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
