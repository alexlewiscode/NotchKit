//
//  ClosedNotchRenderer.swift
//  NotchKit
//
//  Deterministic closed-notch selection and rendering.
//

import NotchExtensionSDK
import NotchExtensionRuntime
import SwiftUI

/// The selected contribution per region plus the resulting chin width.
@MainActor
struct ClosedNotchRenderResult {
    let winners: [ClosedNotchRegion: ClosedNotchContribution]
    let chinWidth: CGFloat
}

/// Selects and renders closed-notch content from a single render snapshot.
///
/// This is the single seam that replaced the scattered `if`/`else if` chain and
/// the parallel chin-width calculation.
@MainActor
enum ClosedNotchRenderer {
    static func render(
        snapshot: ClosedNotchRenderSnapshot,
        contributions: [ClosedNotchContribution],
        recency: [ContributionID: Int] = [:],
        baseChinWidth: CGFloat
    ) -> ClosedNotchRenderResult {
        let winners = ClosedNotchSelection.select(
            from: contributions,
            snapshot: snapshot,
            recency: recency
        )

        let chinWidth: CGFloat
        if let winner = winners[.exclusion], let preferred = winner.preferredChinWidth {
            chinWidth = preferred(snapshot)
        } else {
            chinWidth = baseChinWidth
        }

        return ClosedNotchRenderResult(winners: winners, chinWidth: chinWidth)
    }
}

/// Renders the selected leading/exclusion/trailing content.
///
/// When only the exclusion region is populated (the Phase 1 built-ins), the
/// winner is rendered directly to preserve the original layout. Leading and
/// trailing are reserved for later migrations.
struct ClosedNotchContent: View {
    let result: ClosedNotchRenderResult
    let fallback: AnyView

    var body: some View {
        let leading = result.winners[.leading]
        let exclusion = result.winners[.exclusion]
        let trailing = result.winners[.trailing]

        if leading == nil && trailing == nil {
            if let exclusion {
                exclusion.makeView()
            } else {
                fallback
            }
        } else {
            HStack(spacing: 0) {
                if let leading {
                    leading.makeView()
                }
                if let exclusion {
                    exclusion.makeView()
                }
                if let trailing {
                    trailing.makeView()
                }
            }
        }
    }
}