//
//  ExtensionStateStore.swift
//  NotchExtensionRuntime
//
//  Migration-ready persistence for extension enabled state.
//

import Foundation

/// The persisted extension state.
///
/// `schemaVersion` allows the storage format to migrate without losing user
/// choices. `enabled` is keyed by extension identity.
public struct ExtensionStateSnapshot: Codable, Equatable {
    /// The current persisted schema version.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var enabled: [String: Bool]

    public init(
        schemaVersion: Int = ExtensionStateSnapshot.currentSchemaVersion,
        enabled: [String: Bool] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.enabled = enabled
    }
}

/// Storage for extension enabled state.
public protocol ExtensionStateStore: AnyObject {
    func load() -> ExtensionStateSnapshot?
    func save(_ snapshot: ExtensionStateSnapshot)
}

/// A `UserDefaults`-backed store.
public final class UserDefaultsExtensionStateStore: ExtensionStateStore {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "com.notchkit.extensions.state"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> ExtensionStateSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ExtensionStateSnapshot.self, from: data)
    }

    public func save(_ snapshot: ExtensionStateSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}

/// An in-memory store, useful for tests and previews.
public final class InMemoryExtensionStateStore: ExtensionStateStore {
    public private(set) var snapshot: ExtensionStateSnapshot?

    public init(snapshot: ExtensionStateSnapshot? = nil) {
        self.snapshot = snapshot
    }

    public func load() -> ExtensionStateSnapshot? {
        snapshot
    }

    public func save(_ snapshot: ExtensionStateSnapshot) {
        self.snapshot = snapshot
    }
}
