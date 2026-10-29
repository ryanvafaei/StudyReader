import Foundation

/// SPEC F-19 and ADR-0021. Pure.
enum FrequencyPolicy {
    /// off → nil, low → 0.80, normal → 0.90, high → 0.95.
    static func retention(for frequency: ReviewFrequency) -> Double? {
        switch frequency {
        case .off: nil
        case .low: 0.80
        case .normal: 0.90
        case .high: 0.95
        }
    }

    /// Card override beats the category frequency.
    static func effectiveFrequency(override: ReviewFrequency?, category: ReviewFrequency) -> ReviewFrequency {
        override ?? category
    }

    /// retention(for: effectiveFrequency(override:category:)).
    static func retention(override: ReviewFrequency?, category: ReviewFrequency) -> Double? {
        retention(for: effectiveFrequency(override: override, category: category))
    }

    /// The one suspension rule (ADR-0021), in this order:
    /// 1. cardType == .passive && highlightHasMasteryCards → .mastery
    /// 2. effective frequency == .off → (override == .off ? .user : .frequencyOff)
    /// 3. otherwise nil (not suspended)
    static func suspendedReason(cardType: CardType, highlightHasMasteryCards: Bool,
                                override: ReviewFrequency?, category: ReviewFrequency) -> SuspendedReason? {
        if cardType == .passive && highlightHasMasteryCards {
            return .mastery
        }
        if effectiveFrequency(override: override, category: category) == .off {
            return override == .off ? .user : .frequencyOff
        }
        return nil
    }

    /// SPEC F-15/F-17: a new highlight gets a passive card automatically only if this is true:
    /// frequency != .off && autoCreateCards.
    static func createsCardAutomatically(frequency: ReviewFrequency, autoCreateCards: Bool) -> Bool {
        frequency != .off && autoCreateCards
    }
}
