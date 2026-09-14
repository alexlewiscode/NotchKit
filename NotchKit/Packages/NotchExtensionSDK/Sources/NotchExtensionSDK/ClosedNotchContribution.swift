//
//  ClosedNotchContribution.swift
//  NotchExtensionSDK
//
//  A declarative piece of closed-notch content.
//

import CoreGraphics
import SwiftUI

/// Content an extension contributes to the closed notch.
///
/// Contributions declare a region, priority, and stable tie-breaker. Core
/// selects at most one winner per region deterministically (see
/// `ClosedNotchSelection`).
public struct ClosedNotchContribution: Identifiable {
    /// Stable identity for routing, recency, and tie-breaking.
    public let id: ContributionID
    /// The owning extension identity.
    public let extensionID: ExtensionIdentity
    /// The region this contribution competes in.
    public let region: ClosedNotchRegion
    /// Higher priority wins within a region.
    public let priority: Int
    /// Stable tie-breaker applied after priority and recency.
    public let tieBreaker: String
    /// Whether the contribution can currently be shown.
    public let isAvailable: (ClosedNotchRenderSnapshot) -> Bool
    /// The view factory. Core is responsible for hosting the returned view.
    public let makeView: () -> AnyView
    /// Optional deterministic width for the closed chin when this wins.
    public let preferredChinWidth: ((ClosedNotchRenderSnapshot) -> CGFloat)?

    public init(
        id: ContributionID,
        extensionID: ExtensionIdentity,
        region: ClosedNotchRegion,
        priority: Int,
        tieBreaker: String,
        isAvailable: @escaping (ClosedNotchRenderSnapshot) -> Bool,
        makeView: @escaping () -> AnyView,
        preferredChinWidth: ((ClosedNotchRenderSnapshot) -> CGFloat)? = nil
    ) {
        self.id = id
        self.extensionID = extensionID
        self.region = region
        self.priority = priority
        self.tieBreaker = tieBreaker
        self.isAvailable = isAvailable
        self.makeView = makeView
        self.preferredChinWidth = preferredChinWidth
    }
}
