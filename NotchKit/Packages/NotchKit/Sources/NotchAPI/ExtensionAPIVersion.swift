//
//  ExtensionAPIVersion.swift
//  NotchAPI
//
//  Semantic version describing the extension contract a descriptor targets.
//

import Foundation

/// A semantic version for the extension API.
///
/// Compatibility is determined by the major component only: a descriptor is
/// compatible with the running core when both share the same major version.
public struct ExtensionAPIVersion: Hashable, Comparable, CustomStringConvertible {
    /// The major component. Breaking changes bump this value.
    public let major: Int
    /// The minor component. Additive changes bump this value.
    public let minor: Int
    /// The patch component.
    public let patch: Int

    /// The API version implemented by this build of NotchKit.
    public static let current = ExtensionAPIVersion(major: 1, minor: 0, patch: 0)

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Whether this version is compatible with the running core.
    public var isCompatibleWithCurrent: Bool {
        major == Self.current.major
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: ExtensionAPIVersion, rhs: ExtensionAPIVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
