//
//  ExtensionIdentity.swift
//  NotchAPI
//
//  Stable reverse-DNS identity for a NotchKit extension.
//

import Foundation

/// Errors raised when an identity or destination id is malformed.
public enum ExtensionIdentityError: Error, Equatable {
    /// The supplied string is not a valid reverse-DNS identity.
    case invalidFormat(String)
}

/// A stable reverse-DNS identity for an extension, for example
/// `com.boringnotch.home`.
///
/// Identities are validated at construction and used as the persistence key for
/// enabled state. They must remain stable across releases.
public struct ExtensionIdentity: Hashable, Comparable, CustomStringConvertible {
    /// The validated reverse-DNS string.
    public let rawValue: String

    /// Creates an identity, validating the reverse-DNS format.
    public init(_ rawValue: String) throws {
        try Self.validate(rawValue)
        self.rawValue = rawValue
    }

    /// Creates an identity, validating the reverse-DNS format.
    public init(validating rawValue: String) throws {
        try self.init(rawValue)
    }

    public var description: String { rawValue }

    public static func < (lhs: ExtensionIdentity, rhs: ExtensionIdentity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    private static func validate(_ value: String) throws {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 3, !value.hasPrefix("."), !value.hasSuffix(".") else {
            throw ExtensionIdentityError.invalidFormat(value)
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        for component in components {
            guard !component.isEmpty else {
                throw ExtensionIdentityError.invalidFormat(value)
            }
            guard component.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                throw ExtensionIdentityError.invalidFormat(value)
            }
            guard !component.hasPrefix("-"), !component.hasSuffix("-") else {
                throw ExtensionIdentityError.invalidFormat(value)
            }
        }
    }
}
