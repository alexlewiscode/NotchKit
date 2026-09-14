//
//  ClosedNotchSelection.swift
//  NotchExtensions
//
//  Deterministic per-region selection for closed-notch content.
//

import NotchAPI

/// Selects at most one closed-notch contribution per region.
///
/// Ordering within a region:
/// 1. higher `priority`,
/// 2. higher recency rank (most recently activated first),
/// 3. ascending `tieBreaker`,
/// 4. ascending contribution id.
///
/// Only contributions whose `isAvailable` predicate holds for the supplied
/// snapshot are considered. Callers should remove contributions belonging to
/// disabled extensions before calling.
public enum ClosedNotchSelection {
    public static func select(
        from contributions: [ClosedNotchContribution],
        snapshot: ClosedNotchRenderSnapshot,
        recency: [ContributionID: Int] = [:]
    ) -> [ClosedNotchRegion: ClosedNotchContribution] {
        let available = contributions.filter { $0.isAvailable(snapshot) }
        var result: [ClosedNotchRegion: ClosedNotchContribution] = [:]

        for region in ClosedNotchRegion.allCases {
            let candidates = available
                .filter { $0.region == region }
                .sorted { lhs, rhs in
                    if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                    let lhsRecency = recency[lhs.id] ?? 0
                    let rhsRecency = recency[rhs.id] ?? 0
                    if lhsRecency != rhsRecency { return lhsRecency > rhsRecency }
                    if lhs.tieBreaker != rhs.tieBreaker { return lhs.tieBreaker < rhs.tieBreaker }
                    return lhs.id < rhs.id
                }
            if let winner = candidates.first {
                result[region] = winner
            }
        }

        return result
    }
}
