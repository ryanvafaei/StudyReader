import Testing
import Foundation
@testable import StudyReader

/// One row of the retention table (SPEC F-19 AC1).
struct FrequencyRetentionRow: Sendable {
    let frequency: ReviewFrequency
    let expected: Double?
}

/// One row of the override × category precedence table (SPEC F-19).
struct FrequencyPrecedenceRow: Sendable {
    let override: ReviewFrequency?
    let category: ReviewFrequency
}

/// One row of the suspension table (ADR-0021).
struct FrequencySuspensionRow: Sendable {
    let cardType: CardType
    let hasMastery: Bool
    let override: ReviewFrequency?
    let category: ReviewFrequency
    let expected: SuspendedReason?
}

/// Frequency → retention mapping, precedence and the suspension rule (T98, SPEC F-19, ADR-0021). Pure; no clock or DB.
@Suite struct FrequencyPolicyTests {

    static let retentionRows: [FrequencyRetentionRow] = [
        FrequencyRetentionRow(frequency: .off, expected: nil),
        FrequencyRetentionRow(frequency: .low, expected: 0.80),
        FrequencyRetentionRow(frequency: .normal, expected: 0.90),
        FrequencyRetentionRow(frequency: .high, expected: 0.95),
    ]

    static let precedenceRows: [FrequencyPrecedenceRow] = {
        let overrides: [ReviewFrequency?] = [nil] + ReviewFrequency.allCases
        return overrides.flatMap { override in
            ReviewFrequency.allCases.map { FrequencyPrecedenceRow(override: override, category: $0) }
        }
    }()

    static let suspensionRows: [FrequencySuspensionRow] = [
        // Mastery beats every frequency for a passive card.
        FrequencySuspensionRow(cardType: .passive, hasMastery: true, override: .high, category: .off, expected: .mastery),
        FrequencySuspensionRow(cardType: .passive, hasMastery: true, override: nil, category: .off, expected: .mastery),
        FrequencySuspensionRow(cardType: .passive, hasMastery: true, override: .off, category: .normal, expected: .mastery),
        // Mastery never suspends cloze or Q&A cards.
        FrequencySuspensionRow(cardType: .cloze, hasMastery: true, override: nil, category: .off, expected: .frequencyOff),
        FrequencySuspensionRow(cardType: .qa, hasMastery: true, override: nil, category: .off, expected: .frequencyOff),
        FrequencySuspensionRow(cardType: .cloze, hasMastery: true, override: .off, category: .normal, expected: .user),
        FrequencySuspensionRow(cardType: .qa, hasMastery: true, override: .high, category: .normal, expected: nil),
        FrequencySuspensionRow(cardType: .cloze, hasMastery: false, override: nil, category: .normal, expected: nil),
        // Override off → user, also when the category is high.
        FrequencySuspensionRow(cardType: .passive, hasMastery: false, override: .off, category: .high, expected: .user),
        FrequencySuspensionRow(cardType: .passive, hasMastery: false, override: .off, category: .off, expected: .user),
        // Nothing overridden, category off → frequencyOff.
        FrequencySuspensionRow(cardType: .passive, hasMastery: false, override: nil, category: .off, expected: .frequencyOff),
        // Override set, category off → the override decides.
        FrequencySuspensionRow(cardType: .passive, hasMastery: false, override: .high, category: .off, expected: nil),
        // Nothing set, category normal → not suspended.
        FrequencySuspensionRow(cardType: .passive, hasMastery: false, override: nil, category: .normal, expected: nil),
    ]

    @Test(arguments: retentionRows)
    func retentionMapping(row: FrequencyRetentionRow) {
        #expect(FrequencyPolicy.retention(for: row.frequency) == row.expected)
    }

    @Test(arguments: precedenceRows)
    func precedence(row: FrequencyPrecedenceRow) {
        let expectedFrequency = row.override ?? row.category
        #expect(FrequencyPolicy.effectiveFrequency(override: row.override, category: row.category) == expectedFrequency)
        #expect(FrequencyPolicy.retention(override: row.override, category: row.category)
                == FrequencyPolicy.retention(for: expectedFrequency))
    }

    @Test(arguments: suspensionRows)
    func suspendedReasonRule(row: FrequencySuspensionRow) {
        let reason = FrequencyPolicy.suspendedReason(
            cardType: row.cardType,
            highlightHasMasteryCards: row.hasMastery,
            override: row.override,
            category: row.category
        )
        #expect(reason == row.expected)
    }

    @Test func createsCardAutomaticallyRule() {
        #expect(FrequencyPolicy.createsCardAutomatically(frequency: .off, autoCreateCards: true) == false)
        #expect(FrequencyPolicy.createsCardAutomatically(frequency: .normal, autoCreateCards: false) == false)
        #expect(FrequencyPolicy.createsCardAutomatically(frequency: .low, autoCreateCards: true) == true)
    }
}
