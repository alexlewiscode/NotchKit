//
//  ExtensionVersion.swift
//  NotchExtensionSDK
//
//  Semantic versions and version ranges used by the extension contract.
//

import Foundation

/// A `major.minor.patch` semantic version.
///
/// Used for an extension's own version and for the host/SDK version ranges an
/// extension declares support for. Equality and ordering are component-wise.
public struct ExtensionVersion: Hashable, Comparable, Codable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses a strict `major.minor.patch` string. Returns `nil` for anything
    /// else, including a different number of components.
    public init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]),
              major >= 0, minor >= 0, patch >= 0
        else {
            return nil
        }
        self.init(major: major, minor: minor, patch: patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: ExtensionVersion, rhs: ExtensionVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = ExtensionVersion(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid semantic version '\(raw)'"
            )
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// An inclusive-minimum / exclusive-maximum version range.
///
/// The textual form is `>=1.2.0` (unbounded above) or `>=1.2.0 <2.0.0`.
/// A bare version is treated as an inclusive minimum.
public struct ExtensionVersionRange: Hashable, Codable, Equatable, CustomStringConvertible, Sendable {
    /// Inclusive lower bound.
    public let minimum: ExtensionVersion
    /// Exclusive upper bound. `nil` means "no upper bound".
    public let maximum: ExtensionVersion?

    public init(minimum: ExtensionVersion, maximum: ExtensionVersion? = nil) {
        self.minimum = minimum
        self.maximum = maximum
    }

    /// Whether `version` falls inside the range.
    public func contains(_ version: ExtensionVersion) -> Bool {
        guard version >= minimum else { return false }
        if let maximum { return version < maximum }
        return true
    }

    public var description: String {
        if let maximum { return ">=\(minimum) <\(maximum)" }
        return ">=\(minimum)"
    }

    /// Parses `">=1.2.0"` or `">=1.2.0 <2.0.0"`. Returns `nil` when malformed or
    /// when the maximum is below the minimum.
    public static func parse(_ string: String) -> ExtensionVersionRange? {
        let clauses = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard !clauses.isEmpty else { return nil }

        var minimum: ExtensionVersion?
        var maximum: ExtensionVersion?
        for clause in clauses {
            if clause.hasPrefix(">=") {
                guard let value = ExtensionVersion(String(clause.dropFirst(2))) else { return nil }
                minimum = value
            } else if clause.hasPrefix("<") {
                guard let value = ExtensionVersion(String(clause.dropFirst(1))) else { return nil }
                maximum = value
            } else if let value = ExtensionVersion(clause) {
                minimum = value
            } else {
                return nil
            }
        }

        guard let minimum else { return nil }
        if let maximum, maximum < minimum { return nil }
        return ExtensionVersionRange(minimum: minimum, maximum: maximum)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = ExtensionVersionRange.parse(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid version range '\(raw)'"
            )
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
