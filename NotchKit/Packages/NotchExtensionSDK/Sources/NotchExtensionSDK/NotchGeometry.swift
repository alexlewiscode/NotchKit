//
//  NotchGeometry.swift
//  NotchExtensionSDK
//
//  Read-only notch geometry exposed to extension content views.
//
//  Core owns geometry; extensions never compute or manipulate it. A closed-notch
//  contribution view reads the current geometry from the SwiftUI environment so
//  the same contribution can render independently on every display.
//

import CoreGraphics
import SwiftUI

/// The geometry an extension content view needs to lay itself out.
///
/// This is a snapshot of core-owned values, never a way to change them. It is
/// provided through the SwiftUI environment by the host immediately before a
/// contributed view is rendered.
public struct NotchGeometry: Equatable, Sendable {
    /// Width of the physical closed notch.
    public let closedNotchWidth: CGFloat
    /// Height of the closed notch content area.
    public let closedNotchHeight: CGFloat

    public init(closedNotchWidth: CGFloat, closedNotchHeight: CGFloat) {
        self.closedNotchWidth = closedNotchWidth
        self.closedNotchHeight = closedNotchHeight
    }

    /// A neutral value used when the host has not supplied geometry.
    public static let unspecified = NotchGeometry(closedNotchWidth: 0, closedNotchHeight: 0)
}

private struct NotchGeometryKey: EnvironmentKey {
    static let defaultValue = NotchGeometry.unspecified
}

public extension EnvironmentValues {
    /// Core-owned notch geometry for the current render.
    var notchGeometry: NotchGeometry {
        get { self[NotchGeometryKey.self] }
        set { self[NotchGeometryKey.self] = newValue }
    }
}