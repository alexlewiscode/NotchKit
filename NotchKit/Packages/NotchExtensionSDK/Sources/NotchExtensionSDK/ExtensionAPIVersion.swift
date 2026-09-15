//
//  ExtensionAPIVersion.swift
//  NotchExtensionSDK
//
//  Semantic version describing the extension contract a descriptor targets.
//

import Foundation

/// A semantic version for the extension API.
///
/// Compatibility is determined by the major component only: a descriptor is
/// compatible with the running core when both share the same major version.
public struct ExtensionAPIVersion: Hashable, Comparable, Codable, CustomStringConvertible, Sendable {
    /// The major component. Breaking changes bump this value.
    public let major: Int
    /// The minor component. Additive changes bump this value.
    public let minor: Int
    /// The patch component.
    public let patch: Int

    /// The API version implemented by this build of NotchKit.
    ///
    /// `1.1.0` adds the additive, source-compatible
    /// `ExtensionDefinition.settings` property. The serialized manifest shape is
    /// unchanged, so existing `1.0.0` manifests whose `supportedSDKVersions`
    /// cover `1.x` remain valid; see `docs/architecture/extension-api.md`.
    public static let current = ExtensionAPIVersion(major: 1, minor: 1, patch: 0)

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

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let version = ExtensionVersion(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid API version '\(raw)'"
            )
        }
        self.init(major: version.major, minor: version.minor, patch: version.patch)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public static func < (lhs: ExtensionAPIVersion, rhs: ExtensionAPIVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
