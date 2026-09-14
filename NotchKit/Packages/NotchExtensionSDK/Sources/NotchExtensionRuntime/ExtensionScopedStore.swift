//
//  ExtensionScopedStore.swift
//  NotchExtensionRuntime
//
//  A UserDefaults-backed, per-extension namespaced store.
//

import Foundation
import NotchExtensionSDK

/// A `UserDefaults`-backed store namespaced to one extension identity.
///
/// Keys written by one extension cannot collide with another's or with the
/// host's, because the extension identity is part of the storage key.
public final class UserDefaultsExtensionScopedStore: ExtensionScopedStore {
    public let schemaVersion: Int
    private let defaults: UserDefaults
    private let namespace: String

    public init(
        identity: ExtensionIdentity,
        schemaVersion: Int = 1,
        defaults: UserDefaults = .standard
    ) {
        self.schemaVersion = schemaVersion
        self.defaults = defaults
        self.namespace = "com.notchkit.extensions.store.\(identity.rawValue)"
    }

    private func storageKey(_ key: String) -> String {
        "\(namespace).\(key)"
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: storageKey(key))
    }

    public func set(_ data: Data?, forKey key: String) {
        let storageKey = storageKey(key)
        if let data {
            defaults.set(data, forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }
    }
}