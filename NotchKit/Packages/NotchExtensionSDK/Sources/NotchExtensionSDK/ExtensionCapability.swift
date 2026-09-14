//
//  ExtensionCapability.swift
//  NotchExtensionSDK
//
//  Declares the kinds of contributions an extension provides.
//

import Foundation

/// A capability declares the kind of contribution an extension supplies.
///
/// The registry validates that declared capabilities match the contributions a
/// descriptor actually carries. The raw string form keeps the set open for
/// future, additive capabilities.
public struct ExtensionCapability: Hashable, RawRepresentable, Codable, ExpressibleByStringLiteral, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// The extension contributes at least one open-notch destination.
    public static let openDestination = ExtensionCapability(rawValue: "open-destination")
    /// The extension contributes at least one closed-notch contribution.
    public static let closedNotchContribution = ExtensionCapability(rawValue: "closed-notch-contribution")
    /// The extension contributes at least one settings destination.
    public static let settingsDestination = ExtensionCapability(rawValue: "settings-destination")
}
