//
//  IdentityMigration.swift
//  NotchExtensionRuntime
//
//  Pure, side-effect-free transforms used by the one-time identity migration.
//  The app/helper layer performs I/O; these functions are unit tested.
//

import Foundation
import NotchExtensionSDK

/// Deterministic transforms that map persisted boringNotch state onto the
/// NotchKit namespace. Every function is pure so it can be tested without the
/// file system, the XPC helper, or a running app.
public enum IdentityMigration {
    /// Maps a legacy extension identity (or destination/contribution id) to the
    /// current namespace. Ids outside the legacy namespace are returned
    /// unchanged, which makes the transform idempotent.
    public static func migrateIdentifier(_ identifier: String) -> String {
        guard identifier.hasPrefix(NotchKitIdentity.Legacy.identifierPrefix) else {
            return identifier
        }
        let suffix = identifier.dropFirst(NotchKitIdentity.Legacy.identifierPrefix.count)
        return NotchKitIdentity.identifierPrefix + suffix
    }

    /// Rewrites persisted extension state from the legacy namespace.
    ///
    /// Returns `nil` when `data` is not a decodable state snapshot, so callers
    /// can treat corruption as a retryable failure instead of dropping data.
    public static func migrateExtensionStateData(_ data: Data) -> Data? {
        guard let snapshot = try? JSONDecoder().decode(ExtensionStateSnapshot.self, from: data) else {
            return nil
        }
        var migrated = snapshot
        var enabled: [String: Bool] = [:]
        enabled.reserveCapacity(snapshot.enabled.count)
        for (key, value) in snapshot.enabled {
            enabled[migrateIdentifier(key)] = value
        }
        migrated.enabled = enabled
        return try? JSONEncoder().encode(migrated)
    }

    /// Returns the legacy defaults entries that are not already present in the
    /// destination. Existing NotchKit values are never overwritten.
    public static func missingDefaults(
        legacy: [String: Any],
        isPresent: (String) -> Bool
    ) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in legacy where !isPresent(key) {
            result[key] = value
        }
        return result
    }

    /// Minimal completion record written after a successful migration. Contains
    /// no user data, only counts and flags.
    public struct Summary: Codable, Equatable {
        public var schemaVersion: Int
        public var defaultsMigrated: Int
        public var extensionStateMigrated: Bool
        public var shelfItemsCopied: Bool
        public var invalidBookmarkCount: Int
        public var completedAt: Date

        public init(
            schemaVersion: Int = 1,
            defaultsMigrated: Int,
            extensionStateMigrated: Bool,
            shelfItemsCopied: Bool,
            invalidBookmarkCount: Int,
            completedAt: Date = Date()
        ) {
            self.schemaVersion = schemaVersion
            self.defaultsMigrated = defaultsMigrated
            self.extensionStateMigrated = extensionStateMigrated
            self.shelfItemsCopied = shelfItemsCopied
            self.invalidBookmarkCount = invalidBookmarkCount
            self.completedAt = completedAt
        }

        /// A migration only counts as complete when nothing was left partially
        /// applied. Invalid bookmarks require renewed access, not a retry.
        public var isValidCompletion: Bool {
            defaultsMigrated >= 0 && extensionStateMigrated && shelfItemsCopied
        }
    }
}