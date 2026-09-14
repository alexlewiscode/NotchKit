//
//  ClosedNotchRenderSnapshot.swift
//  NotchAPI
//
//  A single, immutable snapshot of render-relevant state.
//

import Foundation

/// Render-relevant state passed to availability predicates and the closed-notch
/// renderer.
///
/// The snapshot contains only primitives. It never exposes app view models,
/// singleton managers, or window types, so selection stays deterministic within
/// a frame and testable in isolation.
public struct ClosedNotchRenderSnapshot: Equatable {
    /// Whether the notch is currently open.
    public let isNotchOpen: Bool
    /// Whether closed content is suppressed (for example while hidden fullscreen).
    public let isHiddenOnClosed: Bool
    /// Whether media is actively playing.
    public let isMediaActive: Bool
    /// Whether the media player is idle.
    public let isMediaIdle: Bool
    /// The kind of expanding view currently shown, if any.
    public let expandingViewKind: String?
    /// Whether an expanding view is currently shown.
    public let isExpandingViewShown: Bool
    /// The kind of sneak peek currently shown, if any.
    public let sneakPeekKind: String?
    /// Whether a sneak peek is currently visible.
    public let isSneakPeekVisible: Bool
    /// Additional boolean flags keyed by name for feature-specific predicates.
    public let flags: [String: Bool]

    public init(
        isNotchOpen: Bool = false,
        isHiddenOnClosed: Bool = false,
        isMediaActive: Bool = false,
        isMediaIdle: Bool = true,
        expandingViewKind: String? = nil,
        isExpandingViewShown: Bool = false,
        sneakPeekKind: String? = nil,
        isSneakPeekVisible: Bool = false,
        flags: [String: Bool] = [:]
    ) {
        self.isNotchOpen = isNotchOpen
        self.isHiddenOnClosed = isHiddenOnClosed
        self.isMediaActive = isMediaActive
        self.isMediaIdle = isMediaIdle
        self.expandingViewKind = expandingViewKind
        self.isExpandingViewShown = isExpandingViewShown
        self.sneakPeekKind = sneakPeekKind
        self.isSneakPeekVisible = isSneakPeekVisible
        self.flags = flags
    }

    /// Returns the named boolean flag, defaulting to `false`.
    public func flag(_ name: String) -> Bool {
        flags[name] ?? false
    }

    /// An empty snapshot, useful for tests and previews.
    public static let empty = ClosedNotchRenderSnapshot()
}
