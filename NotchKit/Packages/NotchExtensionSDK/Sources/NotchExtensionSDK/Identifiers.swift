//
//  Identifiers.swift
//  NotchExtensionSDK
//
//  Stable identities for destinations and contributions.
//

import Foundation

/// A stable identity for an open-notch destination or settings destination.
public struct DestinationID: Hashable, Comparable, Codable, CustomStringConvertible, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: DestinationID, rhs: DestinationID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A stable identity for a closed-notch contribution.
public struct ContributionID: Hashable, Comparable, Codable, CustomStringConvertible, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: ContributionID, rhs: ContributionID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
